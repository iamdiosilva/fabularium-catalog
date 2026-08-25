import 'dart:async';
import 'dart:isolate';

import 'package:t/t.dart' as t;

import '../models/telegram_group.dart';
import 'telegram_client.dart';

class TelegramGroupsWorker {
  TelegramGroupsWorker._();

  static final TelegramGroupsWorker instance =
      TelegramGroupsWorker._();

  List<TelegramGroup>? _cache;

  Future<List<TelegramGroup>> getGroups({
    bool forceRefresh = false,
  }) async {
    /*
     * Se já carregamos os grupos nesta execução
     * do aplicativo, não consultamos o Telegram
     * novamente.
     */
    if (!forceRefresh && _cache != null) {
      return List<TelegramGroup>.from(
        _cache!,
      );
    }

    final groups =
        await _loadGroupsInIsolate();

    _cache = groups;

    return List<TelegramGroup>.from(
      groups,
    );
  }

  void clearCache() {
    _cache = null;
  }

  Future<List<TelegramGroup>>
      _loadGroupsInIsolate() async {
    final receivePort =
        ReceivePort();

    final errorPort =
        ReceivePort();

    final exitPort =
        ReceivePort();

    final completer =
        Completer<List<TelegramGroup>>();

    StreamSubscription<dynamic>?
        receiveSubscription;

    StreamSubscription<dynamic>?
        errorSubscription;

    StreamSubscription<dynamic>?
        exitSubscription;

    Isolate? isolate;

    void completeError(
      Object error,
    ) {
      if (!completer.isCompleted) {
        completer.completeError(
          error,
        );
      }
    }

    receiveSubscription =
        receivePort.listen(
      (dynamic message) {
        if (message is! Map) {
          return;
        }

        final type =
            message['type'];

        if (type == 'completed') {
          final rawGroups =
              message['groups'];

          if (rawGroups is! List) {
            completeError(
              Exception(
                'Resposta inválida ao carregar grupos.',
              ),
            );

            return;
          }

          final groups =
              <TelegramGroup>[];

          for (final dynamic raw
              in rawGroups) {
            if (raw is! Map) {
              continue;
            }

            try {
              groups.add(
                TelegramGroup(
                  id:
                      raw['id'] as int,
                  title:
                      raw['title'] as String,
                  accessHash:
                      raw['accessHash'] as int?,
                  isChannel:
                      raw['isChannel'] as bool,
                ),
              );
            } catch (_) {}
          }

          if (!completer.isCompleted) {
            completer.complete(
              groups,
            );
          }

          return;
        }

        if (type == 'error') {
          completeError(
            Exception(
              message['error']
                      ?.toString() ??
                  'Erro ao carregar grupos.',
            ),
          );
        }
      },
    );

    errorSubscription =
        errorPort.listen(
      (dynamic error) {
        if (error is List &&
            error.isNotEmpty) {
          completeError(
            Exception(
              error.first.toString(),
            ),
          );

          return;
        }

        completeError(
          Exception(
            error.toString(),
          ),
        );
      },
    );

    exitSubscription =
        exitPort.listen(
      (_) {
        Future<void>.delayed(
          const Duration(
            milliseconds: 50,
          ),
          () {
            if (!completer.isCompleted) {
              completeError(
                Exception(
                  'O worker de grupos '
                  'foi encerrado inesperadamente.',
                ),
              );
            }
          },
        );
      },
    );

    try {
      isolate =
          await Isolate.spawn<SendPort>(
        _telegramGroupsEntryPoint,
        receivePort.sendPort,
        debugName:
            'FabulariumTelegramGroups',
        errorsAreFatal:
            true,
        onError:
            errorPort.sendPort,
        onExit:
            exitPort.sendPort,
      );

      return await completer.future;
    } finally {
      await receiveSubscription
          ?.cancel();

      await errorSubscription
          ?.cancel();

      await exitSubscription
          ?.cancel();

      receivePort.close();
      errorPort.close();
      exitPort.close();

      isolate?.kill(
        priority:
            Isolate.immediate,
      );
    }
  }
}

@pragma(
  'vm:entry-point',
)
Future<void>
    _telegramGroupsEntryPoint(
  SendPort replyPort,
) async {
  final telegramClient =
      TelegramClient.instance;

  try {
    /*
     * Esse TelegramClient é exclusivo
     * deste isolate.
     */
    final client =
        await telegramClient.connect();

    final response =
        await client.messages.getDialogs(
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
    );

    final error =
        response.error;

    if (error != null) {
      throw Exception(
        error.errorMessage,
      );
    }

    final result =
        response.result;

    if (result == null) {
      await telegramClient.disconnect();

      Isolate.exit(
        replyPort,
        <String, dynamic>{
          'type':
              'completed',
          'groups':
              <Map<String, dynamic>>[],
        },
      );
    }

    final dynamic data =
        result;

    List<dynamic> chats =
        [];

    try {
      chats =
          List<dynamic>.from(
        data.chats as List,
      );
    } catch (_) {}

    final groups =
        <Map<String, dynamic>>[];

    for (final dynamic chat
        in chats) {
      final runtimeType =
          chat.runtimeType.toString();

      /*
       * Grupo clássico.
       */
      if (runtimeType ==
          'Chat') {
        try {
          groups.add(
            <String, dynamic>{
              'id':
                  chat.id as int,
              'title':
                  chat.title as String,
              'accessHash':
                  null,
              'isChannel':
                  false,
            },
          );
        } catch (_) {}

        continue;
      }

      /*
       * Supergroup / Gigagroup.
       */
      if (runtimeType ==
          'Channel') {
        bool megagroup =
            false;

        bool gigagroup =
            false;

        try {
          megagroup =
              chat.megagroup ==
                  true;
        } catch (_) {}

        try {
          gigagroup =
              chat.gigagroup ==
                  true;
        } catch (_) {}

        if (!megagroup &&
            !gigagroup) {
          continue;
        }

        int? accessHash;

        try {
          accessHash =
              chat.accessHash as int?;
        } catch (_) {}

        try {
          groups.add(
            <String, dynamic>{
              'id':
                  chat.id as int,
              'title':
                  chat.title as String,
              'accessHash':
                  accessHash,
              'isChannel':
                  true,
            },
          );
        } catch (_) {}
      }
    }

    /*
     * Fazemos inclusive o sort fora
     * do isolate da interface.
     */
    groups.sort(
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

    await telegramClient.disconnect();

    /*
     * Somente Map/List/String/int/bool
     * atravessam para a UI.
     */
    Isolate.exit(
      replyPort,
      <String, dynamic>{
        'type':
            'completed',
        'groups':
            groups,
      },
    );
  } catch (error) {
    try {
      await telegramClient.disconnect();
    } catch (_) {}

    Isolate.exit(
      replyPort,
      <String, dynamic>{
        'type':
            'error',
        'error':
            error.toString(),
      },
    );
  }
}