import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:t/t.dart' as t;

import '../models/telegram_storage_channel.dart';
import 'telegram_client.dart';

class TelegramStorageService {
  TelegramStorageService._();

  static final TelegramStorageService instance =
      TelegramStorageService._();

  static const String defaultChannelTitle =
      'Fabularium Storage';

  static const String defaultChannelAbout =
      'Private storage channel used by Fabularium Catalog. '
      'Do not delete files from this channel manually.';

  static const int maxStorageFileBytes =
      1900 * 1024 * 1024;

  static const String _configFileName =
      'storage_channel.json';

  String _configFilePath() {
    final local =
        Platform.environment[
            'LOCALAPPDATA'];

    return p.join(
      local != null &&
              local.isNotEmpty
          ? local
          : Directory.systemTemp.path,
      'Fabularium',
      'Telegram',
      _configFileName,
    );
  }

  Future<TelegramStorageChannel?>
      loadChannel() async {
    final file =
        File(
      _configFilePath(),
    );

    try {
      if (!await file.exists()) {
        return null;
      }

      final decoded =
          jsonDecode(
        await file.readAsString(),
      );

      if (decoded is! Map) {
        return null;
      }

      final map =
          Map<String, dynamic>.from(
        decoded,
      );

      if (map['version'] != 1 ||
          map['channel'] is! Map) {
        return null;
      }

      return TelegramStorageChannel.fromJson(
        Map<String, dynamic>.from(
          map['channel'] as Map,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveChannel(
    TelegramStorageChannel channel,
  ) async {
    final file =
        File(
      _configFilePath(),
    );

    await file.parent.create(
      recursive: true,
    );

    final tmp =
        File(
      '${file.path}.tmp',
    );

    await tmp.writeAsString(
      jsonEncode(
        <String, dynamic>{
          'version': 1,
          'channel':
              channel.toJson(),
        },
      ),
      flush: true,
    );

    if (await file.exists()) {
      await file.delete();
    }

    await tmp.rename(
      file.path,
    );
  }

  Future<void> selectExistingChannel(
    TelegramStorageChannel channel,
  ) =>
      saveChannel(channel);

  Future<void> clearChannel() async {
    for (final file in <File>[
      File(_configFilePath()),
      File('${_configFilePath()}.tmp'),
    ]) {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  /// Returns every broadcast channel in which the authenticated Telegram
  /// account can publish, including PUBLIC channels.
  ///
  /// Older Fabularium versions intentionally discarded channels with a
  /// username. Community V3 needs the official Catalog/Files channels to be
  /// public while Pending remains private.
  Future<List<TelegramStorageChannel>>
      listAvailableChannels() async {
    final result =
        await _runWorker(
      _listChannelsWorker,
      const <String, dynamic>{},
    );

    final raw =
        result['channels'];

    if (raw is! List) {
      return <TelegramStorageChannel>[];
    }

    final ids =
        <int>{};

    final channels =
        <TelegramStorageChannel>[];

    for (final item in raw) {
      if (item is! Map) {
        continue;
      }

      try {
        final map =
            Map<String, dynamic>.from(
          item,
        );

        final channel =
            TelegramStorageChannel(
          id:
              map['id'] as int,
          accessHash:
              map['accessHash'] as int,
          title:
              map['title'] as String,
          username:
              _nullableString(
            map['username'],
          ),
        );

        if (ids.add(channel.id)) {
          channels.add(
            channel,
          );
        }
      } catch (_) {}
    }

    channels.sort(
      (a, b) =>
          a.title
              .toLowerCase()
              .compareTo(
                b.title.toLowerCase(),
              ),
    );

    return channels;
  }

  Future<TelegramStorageChannel>
      createStorageChannel({
    String title =
        defaultChannelTitle,
    String about =
        defaultChannelAbout,
  }) async {
    final result =
        await _runWorker(
      _createChannelWorker,
      <String, dynamic>{
        'title': title,
        'about': about,
      },
    );

    if (result['id'] is! int ||
        result['accessHash'] is! int ||
        result['title'] is! String) {
      throw const TelegramStorageException(
        'Telegram returned invalid storage channel data.',
      );
    }

    final channel =
        TelegramStorageChannel(
      id:
          result['id'] as int,
      accessHash:
          result['accessHash'] as int,
      title:
          result['title'] as String,
      username:
          _nullableString(
        result['username'],
      ),
    );

    await saveChannel(
      channel,
    );

    return channel;
  }

  Future<Map<String, dynamic>> _runWorker(
    Future<void> Function(
      Map<String, dynamic>,
    ) entry,
    Map<String, dynamic> payload,
  ) async {
    final events =
        ReceivePort();
    final errors =
        ReceivePort();
    final exit =
        ReceivePort();

    final completer =
        Completer<
            Map<String, dynamic>>();

    Isolate? isolate;
    Timer? grace;

    late final StreamSubscription
        eventSubscription;
    late final StreamSubscription
        errorSubscription;
    late final StreamSubscription
        exitSubscription;

    eventSubscription =
        events.listen(
      (raw) {
        if (raw is! Map) {
          return;
        }

        final map =
            Map<dynamic, dynamic>.from(
          raw,
        );

        if (map['type'] ==
                'completed' &&
            !completer.isCompleted) {
          final result =
              map['result'];

          completer.complete(
            result is Map
                ? Map<String, dynamic>.from(
                    result,
                  )
                : <String, dynamic>{},
          );
        } else if (map['type'] ==
                'error' &&
            !completer.isCompleted) {
          completer.completeError(
            TelegramStorageException(
              map['error']?.toString() ??
                  'Telegram storage error.',
            ),
          );
        }
      },
    );

    errorSubscription =
        errors.listen(
      (error) {
        if (!completer.isCompleted) {
          completer.completeError(
            TelegramStorageException(
              error is List &&
                      error.isNotEmpty
                  ? error.first.toString()
                  : error.toString(),
            ),
          );
        }
      },
    );

    exitSubscription =
        exit.listen(
      (_) {
        if (completer.isCompleted) {
          return;
        }

        grace = Timer(
          const Duration(seconds: 1),
          () {
            if (!completer.isCompleted) {
              completer.completeError(
                const TelegramStorageException(
                  'Telegram storage worker stopped unexpectedly.',
                ),
              );
            }
          },
        );
      },
    );

    try {
      isolate =
          await Isolate.spawn<
              Map<String, dynamic>>(
        entry,
        <String, dynamic>{
          ...payload,
          'eventPort':
              events.sendPort,
        },
        errorsAreFatal: true,
        onError:
            errors.sendPort,
        onExit:
            exit.sendPort,
      );

      return await completer.future;
    } finally {
      grace?.cancel();
      isolate?.kill(
        priority:
            Isolate.immediate,
      );

      await eventSubscription.cancel();
      await errorSubscription.cancel();
      await exitSubscription.cancel();

      events.close();
      errors.close();
      exit.close();
    }
  }
}

@pragma('vm:entry-point')
Future<void> _listChannelsWorker(
  Map<String, dynamic> bootstrap,
) async {
  final port =
      bootstrap['eventPort'];

  if (port is! SendPort) {
    return;
  }

  final telegram =
      TelegramClient.instance;

  try {
    final client =
        await telegram.connect();

    final response =
        await client.messages
            .getDialogs(
      excludePinned: false,
      offsetDate:
          DateTime.fromMillisecondsSinceEpoch(
        0,
      ),
      offsetId: 0,
      offsetPeer:
          const t.InputPeerEmpty(),
      limit: 100,
      hash: 0,
    ).timeout(
      const Duration(
        seconds: 30,
      ),
    );

    if (response.error != null) {
      throw Exception(
        response.error!
            .errorMessage,
      );
    }

    final dynamic result =
        response.result;

    final channels =
        <Map<String, dynamic>>[];

    if (result != null) {
      List<dynamic> chats =
          <dynamic>[];

      try {
        chats =
            List<dynamic>.from(
          result.chats as List,
        );
      } catch (_) {}

      for (final raw in chats) {
        if (raw is! t.Channel) {
          continue;
        }

        final dynamic channel =
            raw;

        bool broadcast = false;
        bool megagroup = false;
        bool gigagroup = false;
        bool creator = false;
        bool canPost = false;
        String? username;

        try {
          broadcast =
              channel.broadcast ==
                  true;
        } catch (_) {}

        try {
          megagroup =
              channel.megagroup ==
                  true;
        } catch (_) {}

        try {
          gigagroup =
              channel.gigagroup ==
                  true;
        } catch (_) {}

        if (!broadcast ||
            megagroup ||
            gigagroup) {
          continue;
        }

        try {
          username =
              channel.username
                  as String?;
        } catch (_) {}

        try {
          creator =
              channel.creator ==
                  true;
        } catch (_) {}

        try {
          final dynamic rights =
              channel.adminRights;

          if (rights != null) {
            canPost =
                rights.postMessages ==
                    true;
          }
        } catch (_) {}

        if (!creator &&
            !canPost) {
          continue;
        }

        try {
          final int id =
              channel.id as int;

          final int? hash =
              channel.accessHash
                  as int?;

          final String title =
              channel.title
                  as String;

          if (hash != null &&
              title.trim().isNotEmpty) {
            channels.add(
              <String, dynamic>{
                'id': id,
                'accessHash':
                    hash,
                'title': title,
                'username':
                    _nullableString(
                  username,
                ),
              },
            );
          }
        } catch (_) {}
      }
    }

    port.send(
      <String, dynamic>{
        'type': 'completed',
        'result':
            <String, dynamic>{
          'channels': channels,
        },
      },
    );
  } catch (error, stackTrace) {
    port.send(
      <String, dynamic>{
        'type': 'error',
        'error':
            error.toString(),
        'stackTrace':
            stackTrace.toString(),
      },
    );
  } finally {
    try {
      await telegram.disconnect();
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
Future<void> _createChannelWorker(
  Map<String, dynamic> bootstrap,
) async {
  final port =
      bootstrap['eventPort'];

  if (port is! SendPort) {
    return;
  }

  final telegram =
      TelegramClient.instance;

  try {
    final client =
        await telegram.connect();

    final response =
        await client.invoke(
      t.ChannelsCreateChannel(
        title:
            bootstrap['title']
                    ?.toString() ??
                TelegramStorageService
                    .defaultChannelTitle,
        about:
            bootstrap['about']
                    ?.toString() ??
                '',
        broadcast: true,
        megagroup: false,
        forImport: false,
        forum: false,
      ),
    ).timeout(
      const Duration(
        seconds: 30,
      ),
    );

    if (response.error != null) {
      throw Exception(
        response.error!
            .errorMessage,
      );
    }

    final dynamic updates =
        response.result;

    List<dynamic> chats =
        <dynamic>[];

    try {
      chats =
          List<dynamic>.from(
        updates.chats as List,
      );
    } catch (_) {}

    for (final raw in chats) {
      if (raw is t.Channel &&
          raw.accessHash != null) {
        String? username;

        try {
          username =
              raw.username;
        } catch (_) {}

        port.send(
          <String, dynamic>{
            'type':
                'completed',
            'result':
                <String, dynamic>{
              'id':
                  raw.id,
              'accessHash':
                  raw.accessHash,
              'title':
                  raw.title,
              'username':
                  _nullableString(
                username,
              ),
            },
          },
        );

        return;
      }
    }

    throw Exception(
      'Storage channel was created, but its accessHash could not be read.',
    );
  } catch (error, stackTrace) {
    port.send(
      <String, dynamic>{
        'type': 'error',
        'error':
            error.toString(),
        'stackTrace':
            stackTrace.toString(),
      },
    );
  } finally {
    try {
      await telegram.disconnect();
    } catch (_) {}
  }
}

String? _nullableString(
  dynamic value,
) {
  final text =
      value?.toString().trim() ?? '';

  return text.isEmpty
      ? null
      : text;
}

class TelegramStorageException
    implements Exception {
  final String message;
  final String? stackTrace;

  const TelegramStorageException(
    this.message, {
    this.stackTrace,
  });

  @override
  String toString() =>
      message;
}

class TelegramStorageFileTooLargeException
    extends TelegramStorageException {
  final int fileSize;
  final int maxSize;

  TelegramStorageFileTooLargeException({
    required this.fileSize,
    required this.maxSize,
  }) : super(
          'File is too large for a single Telegram storage part.',
        );
}
