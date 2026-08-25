import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

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

  /*
   * Mantemos margem abaixo de 2 GB.
   */
  static const int maxStorageFileBytes =
      1900 * 1024 * 1024;

  static const String _configFileName =
      'storage_channel.json';

  // ============================================================
  // GENERIC STORAGE WORKER
  // ============================================================

  Future<Map<String, dynamic>> _runWorker({
    required Future<void> Function(
      Map<String, dynamic> bootstrap,
    )
        entryPoint,
    required Map<String, dynamic> payload,
    void Function(double progress)?
        onProgress,
  }) async {
    final eventPort =
        ReceivePort();

    final errorPort =
        ReceivePort();

    final exitPort =
        ReceivePort();

    final completer =
        Completer<Map<String, dynamic>>();

    StreamSubscription<dynamic>?
        eventSubscription;

    StreamSubscription<dynamic>?
        errorSubscription;

    StreamSubscription<dynamic>?
        exitSubscription;

    Isolate? isolate;

    eventSubscription =
        eventPort.listen(
      (
        dynamic rawMessage,
      ) {
        if (rawMessage is! Map) {
          return;
        }

        final message =
            Map<dynamic, dynamic>.from(
          rawMessage,
        );

        final type =
            message['type'];

        if (type == 'progress') {
          final value =
              message['value'];

          if (value is num) {
            onProgress?.call(
              value
                  .toDouble()
                  .clamp(
                    0.0,
                    1.0,
                  ),
            );
          }

          return;
        }

        if (type == 'completed') {
          if (completer.isCompleted) {
            return;
          }

          final result =
              message['result'];

          if (result is Map) {
            completer.complete(
              Map<String, dynamic>.from(
                result,
              ),
            );
          } else {
            completer.complete(
              <String, dynamic>{},
            );
          }

          return;
        }

        if (type == 'error') {
          if (completer.isCompleted) {
            return;
          }

          final error =
              message['error']
                      ?.toString() ??
                  'Unknown Telegram storage error.';

          final stackTrace =
              message['stackTrace']
                  ?.toString();

          completer.completeError(
            TelegramStorageException(
              error,
              stackTrace:
                  stackTrace,
            ),
          );
        }
      },
    );

    errorSubscription =
        errorPort.listen(
      (
        dynamic rawError,
      ) {
        if (completer.isCompleted) {
          return;
        }

        String errorMessage =
            rawError.toString();

        if (rawError is List &&
            rawError.isNotEmpty) {
          errorMessage =
              rawError.first.toString();
        }

        completer.completeError(
          TelegramStorageException(
            errorMessage,
          ),
        );
      },
    );

    exitSubscription =
        exitPort.listen(
      (_) {
        if (completer.isCompleted) {
          return;
        }

        completer.completeError(
          const TelegramStorageException(
            'Telegram storage worker stopped unexpectedly.',
          ),
        );
      },
    );

    try {
      isolate =
          await Isolate.spawn<
              Map<String, dynamic>>(
        entryPoint,
        <String, dynamic>{
          ...payload,
          'eventPort':
              eventPort.sendPort,
        },
        errorsAreFatal:
            true,
        onError:
            errorPort.sendPort,
        onExit:
            exitPort.sendPort,
        debugName:
            'FabulariumTelegramStorageWorker',
      );

      return await completer.future;
    } finally {
      isolate?.kill(
        priority:
            Isolate.immediate,
      );

      await eventSubscription.cancel();
      await errorSubscription.cancel();
      await exitSubscription.cancel();

      eventPort.close();
      errorPort.close();
      exitPort.close();
    }
  }

  // ============================================================
  // LOCAL CONFIG
  // ============================================================

  String _configFilePath() {
    final localAppData =
        Platform.environment[
            'LOCALAPPDATA'];

    final basePath =
        localAppData != null &&
                localAppData.isNotEmpty
            ? localAppData
            : Directory.systemTemp.path;

    return p.join(
      basePath,
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

      final raw =
          await file.readAsString();

      final decoded =
          jsonDecode(
        raw,
      );

      if (decoded is! Map) {
        return null;
      }

      final map =
          Map<String, dynamic>.from(
        decoded,
      );

      if (map['version'] != 1) {
        return null;
      }

      final channelData =
          map['channel'];

      if (channelData is! Map) {
        return null;
      }

      return TelegramStorageChannel
          .fromJson(
        Map<String, dynamic>.from(
          channelData,
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
      recursive:
          true,
    );

    final temp =
        File(
      '${file.path}.tmp',
    );

    await temp.writeAsString(
      jsonEncode(
        <String, dynamic>{
          'version':
              1,
          'channel':
              channel.toJson(),
        },
      ),
      flush:
          true,
    );

    if (await file.exists()) {
      await file.delete();
    }

    await temp.rename(
      file.path,
    );
  }

  Future<void> selectExistingChannel(
    TelegramStorageChannel channel,
  ) {
    return saveChannel(
      channel,
    );
  }

  Future<void> clearChannel() async {
    final file =
        File(
      _configFilePath(),
    );

    final temp =
        File(
      '${file.path}.tmp',
    );

    for (final candidate
        in <File>[
      file,
      temp,
    ]) {
      try {
        if (await candidate.exists()) {
          await candidate.delete();
        }
      } catch (_) {}
    }
  }

  // ============================================================
  // EXISTING CHANNELS
  // ============================================================

  Future<List<TelegramStorageChannel>>
      listAvailableChannels() async {
    final result =
        await _runWorker(
      entryPoint:
          _telegramStorageListChannelsEntryPoint,
      payload:
          const <String, dynamic>{},
    );

    final rawChannels =
        result['channels'];

    if (rawChannels is! List) {
      return <TelegramStorageChannel>[];
    }

    final channels =
        <TelegramStorageChannel>[];

    final ids =
        <int>{};

    for (final dynamic raw
        in rawChannels) {
      if (raw is! Map) {
        continue;
      }

      try {
        final map =
            Map<String, dynamic>.from(
          raw,
        );

        final channel =
            TelegramStorageChannel(
          id:
              map['id'] as int,
          accessHash:
              map['accessHash'] as int,
          title:
              map['title'] as String,
        );

        if (!ids.add(
          channel.id,
        )) {
          continue;
        }

        channels.add(
          channel,
        );
      } catch (_) {}
    }

    channels.sort(
      (
        a,
        b,
      ) =>
          a.title
              .toLowerCase()
              .compareTo(
                b.title.toLowerCase(),
              ),
    );

    return channels;
  }

  // ============================================================
  // CREATE STORAGE CHANNEL
  // ============================================================

  Future<TelegramStorageChannel>
      createStorageChannel({
    String title =
        defaultChannelTitle,
    String about =
        defaultChannelAbout,
  }) async {
    final result =
        await _runWorker(
      entryPoint:
          _telegramStorageCreateChannelEntryPoint,
      payload:
          <String, dynamic>{
        'title':
            title,
        'about':
            about,
      },
    );

    final id =
        result['id'];

    final accessHash =
        result['accessHash'];

    final channelTitle =
        result['title'];

    if (id is! int ||
        accessHash is! int ||
        channelTitle is! String) {
      throw const TelegramStorageException(
        'Telegram returned invalid storage channel data.',
      );
    }

    final channel =
        TelegramStorageChannel(
      id:
          id,
      accessHash:
          accessHash,
      title:
          channelTitle,
    );

    await saveChannel(
      channel,
    );

    return channel;
  }

  // ============================================================
  // UPLOAD
  // ============================================================

  Future<TelegramStorageUploadResult>
      uploadFile({
    required TelegramStorageChannel
        channel,
    required String filePath,
    void Function(double progress)?
        onProgress,
  }) async {
    final file =
        File(
      filePath,
    );

    if (!await file.exists()) {
      throw const TelegramStorageException(
        'The selected file no longer exists.',
      );
    }

    final fileSize =
        await file.length();

    if (fileSize <= 0) {
      throw const TelegramStorageException(
        'Empty files cannot be uploaded.',
      );
    }

    if (fileSize >
        maxStorageFileBytes) {
      throw TelegramStorageFileTooLargeException(
        fileSize:
            fileSize,
        maxSize:
            maxStorageFileBytes,
      );
    }

    final result =
        await _runWorker(
      entryPoint:
          _telegramStorageUploadEntryPoint,
      payload:
          <String, dynamic>{
        'filePath':
            filePath,
        'channelId':
            channel.id,
        'accessHash':
            channel.accessHash,
      },
      onProgress:
          onProgress,
    );

    return TelegramStorageUploadResult(
      fileName:
          result['fileName']
                  ?.toString() ??
              p.basename(
                filePath,
              ),
      size:
          result['size'] is int
              ? result['size'] as int
              : fileSize,
      messageId:
          result['messageId'] as int?,
    );
  }
}

// ============================================================
// LIST EXISTING CHANNELS WORKER
// ============================================================

@pragma(
  'vm:entry-point',
)
Future<void>
    _telegramStorageListChannelsEntryPoint(
  Map<String, dynamic> bootstrap,
) async {
  final eventPort =
      bootstrap['eventPort'];

  if (eventPort is! SendPort) {
    return;
  }

  final telegramClient =
      TelegramClient.instance;

  try {
    final client =
        await telegramClient.connect();

    /*
     * Primeiro suporte:
     *
     * consultamos os 100 dialogs mais recentes.
     *
     * O Telegram normalmente limita métodos
     * paginados deste tipo a 100 itens por request.
     *
     * Caso seja necessário, depois podemos
     * paginar também a seleção dos canais.
     */
    final response =
        await client.messages
            .getDialogs(
      excludePinned:
          false,
      offsetDate:
          DateTime.fromMillisecondsSinceEpoch(
        0,
      ),
      offsetId:
          0,
      offsetPeer:
          const t.InputPeerEmpty(),
      limit:
          100,
      hash:
          0,
    )
            .timeout(
      const Duration(
        seconds:
            30,
      ),
    );

    final error =
        response.error;

    if (error != null) {
      throw Exception(
        error.errorMessage,
      );
    }

    final dynamic result =
        response.result;

    if (result == null) {
      eventPort.send(
        <String, dynamic>{
          'type':
              'completed',
          'result':
              <String, dynamic>{
            'channels':
                <Map<String, dynamic>>[],
          },
        },
      );

      return;
    }

    List<dynamic> chats =
        <dynamic>[];

    try {
      chats =
          List<dynamic>.from(
        result.chats as List,
      );
    } catch (_) {}

    final channels =
        <Map<String, dynamic>>[];

    for (final dynamic rawChat
        in chats) {
      if (rawChat is! t.Channel) {
        continue;
      }

      final dynamic channel =
          rawChat;

      bool broadcast =
          false;

      bool megagroup =
          false;

      bool gigagroup =
          false;

      bool creator =
          false;

      bool canPostMessages =
          false;

      int? accessHash;

      int? id;

      String? title;

      String? username;

      // --------------------------------------------------------
      // CHANNEL TYPE
      // --------------------------------------------------------

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

      /*
       * Storage usa channel broadcast.
       *
       * Supergroups continuam sendo usados
       * normalmente pela tela de grupos,
       * mas não entram no seletor de Storage.
       */
      if (!broadcast ||
          megagroup ||
          gigagroup) {
        continue;
      }

      // --------------------------------------------------------
      // PRIVATE CHANNEL
      // --------------------------------------------------------

      try {
        username =
            channel.username
                as String?;
      } catch (_) {}

      bool hasPublicUsername =
          username != null &&
              username.trim().isNotEmpty;

      /*
       * Layers recentes podem possuir usernames
       * adicionais.
       */
      try {
        final dynamic rawUsernames =
            channel.usernames;

        if (rawUsernames != null) {
          final usernames =
              List<dynamic>.from(
            rawUsernames as List,
          );

          for (final dynamic item
              in usernames) {
            String? value;

            bool active =
                true;

            try {
              value =
                  item.username
                      as String?;
            } catch (_) {}

            try {
              active =
                  item.active ==
                      true;
            } catch (_) {}

            if (active &&
                value != null &&
                value.trim().isNotEmpty) {
              hasPublicUsername =
                  true;

              break;
            }
          }
        }
      } catch (_) {}

      /*
       * O seletor é propositalmente dedicado
       * a canais privados.
       */
      if (hasPublicUsername) {
        continue;
      }

      // --------------------------------------------------------
      // WRITE PERMISSION
      // --------------------------------------------------------

      try {
        creator =
            channel.creator ==
                true;
      } catch (_) {}

      try {
        final dynamic adminRights =
            channel.adminRights;

        if (adminRights != null) {
          canPostMessages =
              adminRights
                      .postMessages ==
                  true;
        }
      } catch (_) {}

      /*
       * Em canal broadcast um usuário comum
       * não pode publicar.
       *
       * Aceitamos:
       *
       * - owner;
       * - admin com post_messages.
       */
      if (!creator &&
          !canPostMessages) {
        continue;
      }

      // --------------------------------------------------------
      // IDENTIFIERS
      // --------------------------------------------------------

      try {
        id =
            channel.id as int;
      } catch (_) {}

      try {
        accessHash =
            channel.accessHash
                as int?;
      } catch (_) {}

      try {
        title =
            channel.title
                as String;
      } catch (_) {}

      if (id == null ||
          accessHash == null ||
          title == null ||
          title.trim().isEmpty) {
        continue;
      }

      channels.add(
        <String, dynamic>{
          'id':
              id,
          'accessHash':
              accessHash,
          'title':
              title,
        },
      );
    }

    channels.sort(
      (
        a,
        b,
      ) {
        final titleA =
            (a['title'] as String)
                .toLowerCase();

        final titleB =
            (b['title'] as String)
                .toLowerCase();

        return titleA.compareTo(
          titleB,
        );
      },
    );

    eventPort.send(
      <String, dynamic>{
        'type':
            'completed',
        'result':
            <String, dynamic>{
          'channels':
              channels,
        },
      },
    );
  } catch (
    error,
    stackTrace
  ) {
    eventPort.send(
      <String, dynamic>{
        'type':
            'error',
        'error':
            error.toString(),
        'stackTrace':
            stackTrace.toString(),
      },
    );
  } finally {
    try {
      await telegramClient.disconnect();
    } catch (_) {}
  }
}

// ============================================================
// CREATE CHANNEL WORKER
// ============================================================

@pragma(
  'vm:entry-point',
)
Future<void>
    _telegramStorageCreateChannelEntryPoint(
  Map<String, dynamic> bootstrap,
) async {
  final eventPort =
      bootstrap['eventPort'];

  if (eventPort is! SendPort) {
    return;
  }

  final title =
      bootstrap['title']
              ?.toString() ??
          TelegramStorageService
              .defaultChannelTitle;

  final about =
      bootstrap['about']
              ?.toString() ??
          TelegramStorageService
              .defaultChannelAbout;

  final telegramClient =
      TelegramClient.instance;

  try {
    final client =
        await telegramClient.connect();

    final response =
        await client
            .invoke(
      t.ChannelsCreateChannel(
        title:
            title,
        about:
            about,
        broadcast:
            true,
        megagroup:
            false,
        forImport:
            false,
        forum:
            false,
      ),
    )
            .timeout(
      const Duration(
        seconds:
            30,
      ),
    );

    final error =
        response.error;

    if (error != null) {
      throw Exception(
        error.errorMessage,
      );
    }

    final dynamic updates =
        response.result;

    if (updates == null) {
      throw Exception(
        'Telegram did not return channel information.',
      );
    }

    List<dynamic> chats =
        <dynamic>[];

    try {
      chats =
          List<dynamic>.from(
        updates.chats as List,
      );
    } catch (_) {}

    for (final dynamic chat
        in chats) {
      if (chat is! t.Channel) {
        continue;
      }

      final accessHash =
          chat.accessHash;

      if (accessHash == null) {
        continue;
      }

      eventPort.send(
        <String, dynamic>{
          'type':
              'completed',
          'result':
              <String, dynamic>{
            'id':
                chat.id,
            'accessHash':
                accessHash,
            'title':
                chat.title,
          },
        },
      );

      return;
    }

    throw Exception(
      'Storage channel was created, '
      'but its accessHash could not be read.',
    );
  } catch (
    error,
    stackTrace
  ) {
    eventPort.send(
      <String, dynamic>{
        'type':
            'error',
        'error':
            error.toString(),
        'stackTrace':
            stackTrace.toString(),
      },
    );
  } finally {
    try {
      await telegramClient.disconnect();
    } catch (_) {}
  }
}

// ============================================================
// UPLOAD WORKER
// ============================================================

@pragma(
  'vm:entry-point',
)
Future<void>
    _telegramStorageUploadEntryPoint(
  Map<String, dynamic> bootstrap,
) async {
  final eventPort =
      bootstrap['eventPort'];

  if (eventPort is! SendPort) {
    return;
  }

  final filePath =
      bootstrap['filePath'];

  final channelId =
      bootstrap['channelId'];

  final accessHash =
      bootstrap['accessHash'];

  if (filePath is! String ||
      channelId is! int ||
      accessHash is! int) {
    eventPort.send(
      <String, dynamic>{
        'type':
            'error',
        'error':
            'Invalid Telegram storage upload request.',
      },
    );

    return;
  }

  final telegramClient =
      TelegramClient.instance;

  RandomAccessFile? input;

  try {
    final file =
        File(
      filePath,
    );

    if (!await file.exists()) {
      throw Exception(
        'File not found: $filePath',
      );
    }

    final fileSize =
        await file.length();

    if (fileSize <= 0) {
      throw Exception(
        'Cannot upload an empty file.',
      );
    }

    if (fileSize >
        TelegramStorageService
            .maxStorageFileBytes) {
      throw Exception(
        'File exceeds current Fabularium '
        'storage part limit.',
      );
    }

    final client =
        await telegramClient.connect();

    final peer =
        t.InputPeerChannel(
      channelId:
          channelId,
      accessHash:
          accessHash,
    );

    const partSize =
        512 * 1024;

    final totalParts =
        (fileSize +
                partSize -
                1) ~/
            partSize;

    final isBig =
        fileSize >=
            10 * 1024 * 1024;

    final fileId =
        _telegramStorageRandom64();

    final fileName =
        p.basename(
      filePath,
    );

    input =
        await file.open(
      mode:
          FileMode.read,
    );

    int uploadedBytes =
        0;

    for (int partIndex = 0;
        partIndex < totalParts;
        partIndex++) {
      final remaining =
          fileSize -
              uploadedBytes;

      final length =
          min(
        partSize,
        remaining,
      );

      final bytes =
          await input.read(
        length,
      );

      if (bytes.isEmpty) {
        throw Exception(
          'Unexpected end of file '
          'while uploading part $partIndex.',
        );
      }

      final response =
          isBig
              ? await client
                  .invoke(
                    t.UploadSaveBigFilePart(
                      fileId:
                          fileId,
                      filePart:
                          partIndex,
                      fileTotalParts:
                          totalParts,
                      bytes:
                          bytes,
                    ),
                  )
                  .timeout(
                    const Duration(
                      seconds:
                          60,
                    ),
                  )
              : await client
                  .invoke(
                    t.UploadSaveFilePart(
                      fileId:
                          fileId,
                      filePart:
                          partIndex,
                      bytes:
                          bytes,
                    ),
                  )
                  .timeout(
                    const Duration(
                      seconds:
                          60,
                    ),
                  );

      final error =
          response.error;

      if (error != null) {
        throw Exception(
          'Telegram upload failed '
          'on part ${partIndex + 1}/'
          '$totalParts: '
          '${error.errorMessage}',
        );
      }

      uploadedBytes +=
          bytes.length;

      final uploadProgress =
          uploadedBytes /
              fileSize;

      eventPort.send(
        <String, dynamic>{
          'type':
              'progress',
          'value':
              uploadProgress *
                  0.95,
        },
      );
    }

    final inputFile =
        isBig
            ? t.InputFileBig(
                id:
                    fileId,
                parts:
                    totalParts,
                name:
                    fileName,
              )
            : t.InputFile(
                id:
                    fileId,
                parts:
                    totalParts,
                name:
                    fileName,
                md5Checksum:
                    '',
              );

    eventPort.send(
      <String, dynamic>{
        'type':
            'progress',
        'value':
            0.96,
      },
    );

    final sendResponse =
        await client
            .invoke(
      t.MessagesSendMedia(
        silent:
            true,
        background:
            true,
        clearDraft:
            false,
        noforwards:
            false,
        updateStickersetsOrder:
            false,
        invertMedia:
            false,
        allowPaidFloodskip:
            false,
        peer:
            peer,
        media:
            t.InputMediaUploadedDocument(
          nosoundVideo:
              false,
          forceFile:
              true,
          spoiler:
              false,
          file:
              inputFile,
          mimeType:
              'application/octet-stream',
          attributes:
              <t.DocumentAttributeBase>[
            t.DocumentAttributeFilename(
              fileName:
                  fileName,
            ),
          ],
        ),
        message:
            '[FABULARIUM_STORAGE_FILE_V1] '
            '$fileName',
        randomId:
            _telegramStorageRandom64(),
      ),
    )
            .timeout(
      const Duration(
        seconds:
            60,
      ),
    );

    final sendError =
        sendResponse.error;

    if (sendError != null) {
      throw Exception(
        'Telegram could not publish the '
        'uploaded file: '
        '${sendError.errorMessage}',
      );
    }

    final messageId =
        _extractTelegramStorageMessageId(
      sendResponse.result,
    );

    eventPort.send(
      <String, dynamic>{
        'type':
            'progress',
        'value':
            1.0,
      },
    );

    eventPort.send(
      <String, dynamic>{
        'type':
            'completed',
        'result':
            <String, dynamic>{
          'fileName':
              fileName,
          'size':
              fileSize,
          'messageId':
              messageId,
        },
      },
    );
  } catch (
    error,
    stackTrace
  ) {
    eventPort.send(
      <String, dynamic>{
        'type':
            'error',
        'error':
            error.toString(),
        'stackTrace':
            stackTrace.toString(),
      },
    );
  } finally {
    try {
      await input?.close();
    } catch (_) {}

    try {
      await telegramClient.disconnect();
    } catch (_) {}
  }
}

// ============================================================
// TELEGRAM HELPERS
// ============================================================

int _telegramStorageRandom64() {
  final random =
      Random.secure();

  final high =
      random.nextInt(
    1 << 31,
  );

  final low =
      random.nextInt(
    1 << 32,
  );

  final value =
      (high << 32) |
          low;

  return value == 0
      ? 1
      : value;
}

int? _extractTelegramStorageMessageId(
  dynamic updates,
) {
  if (updates == null) {
    return null;
  }

  if (updates
      is t.UpdateShortSentMessage) {
    return updates.id;
  }

  List<dynamic> rawUpdates =
      <dynamic>[];

  try {
    rawUpdates =
        List<dynamic>.from(
      updates.updates as List,
    );
  } catch (_) {}

  for (final dynamic update
      in rawUpdates) {
    if (update
        is t.UpdateNewChannelMessage) {
      final dynamic message =
          update.message;

      try {
        return message.id as int;
      } catch (_) {}
    }

    if (update
        is t.UpdateNewMessage) {
      final dynamic message =
          update.message;

      try {
        return message.id as int;
      } catch (_) {}
    }
  }

  return null;
}

// ============================================================
// RESULT
// ============================================================

class TelegramStorageUploadResult {
  final String fileName;

  final int size;

  final int? messageId;

  const TelegramStorageUploadResult({
    required this.fileName,
    required this.size,
    required this.messageId,
  });
}

// ============================================================
// EXCEPTIONS
// ============================================================

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
          'File is too large for a single '
          'Telegram storage part. '
          'Size: ${_formatStorageBytes(fileSize)}. '
          'Current limit: '
          '${_formatStorageBytes(maxSize)}.',
        );
}

String _formatStorageBytes(
  int bytes,
) {
  const mb =
      1024 * 1024;

  const gb =
      mb * 1024;

  if (bytes >= gb) {
    return '${(bytes / gb).toStringAsFixed(2)} GB';
  }

  return '${(bytes / mb).toStringAsFixed(2)} MB';
}