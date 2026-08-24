import 'dart:async';
import 'dart:isolate';

import '../models/telegram_media.dart';
import 'telegram_client.dart';
import 'telegram_download_engine.dart';

class TelegramDownloadWorker {
  TelegramDownloadWorker._();

  static final TelegramDownloadWorker instance =
      TelegramDownloadWorker._();

  Future<String> downloadMedia(
    TelegramMedia media, {
    required String groupTitle,
    void Function(
      int received,
      int total,
    )?
        onProgress,
  }) async {
    final messagePort =
        ReceivePort();

    final errorPort =
        ReceivePort();

    final exitPort =
        ReceivePort();

    final completer =
        Completer<String>();

    StreamSubscription<dynamic>?
        messageSubscription;

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

    messageSubscription =
        messagePort.listen(
      (dynamic message) {
        if (message
            is! Map) {
          return;
        }

        final type =
            message['type'];

        if (type ==
            'progress') {
          final received =
              message['received'];

          final total =
              message['total'];

          if (received is int &&
              total is int) {
            onProgress?.call(
              received,
              total,
            );
          }

          return;
        }

        if (type ==
            'completed') {
          final path =
              message['path'];

          if (path is String &&
              !completer.isCompleted) {
            completer.complete(
              path,
            );
          }

          return;
        }

        if (type ==
            'error') {
          final error =
              message['error'];

          final stackTrace =
              message['stackTrace'];

          completeError(
            TelegramDownloadWorkerException(
              error?.toString() ??
                  'Erro desconhecido no download.',
              stackTrace:
                  stackTrace?.toString(),
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
          final message =
              error.first
                  .toString();

          final stack =
              error.length >
                      1
                  ? error[1]
                      .toString()
                  : null;

          completeError(
            TelegramDownloadWorkerException(
              message,
              stackTrace:
                  stack,
            ),
          );

          return;
        }

        completeError(
          TelegramDownloadWorkerException(
            error.toString(),
          ),
        );
      },
    );

    exitSubscription =
        exitPort.listen(
      (_) {
        /*
         * Isolate.exit() envia a mensagem
         * final imediatamente antes da saída.
         *
         * Damos um pequeno tempo para essa
         * mensagem chegar antes de considerar
         * a saída inesperada.
         */
        Future<void>.delayed(
          const Duration(
            milliseconds:
                50,
          ),
          () {
            if (!completer.isCompleted) {
              completeError(
                const TelegramDownloadWorkerException(
                  'O processo de download '
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
          await Isolate.spawn<
              _TelegramDownloadWorkerRequest>(
        _telegramDownloadWorkerEntryPoint,
        _TelegramDownloadWorkerRequest(
          replyPort:
              messagePort.sendPort,
          media:
              media,
          groupTitle:
              groupTitle,
        ),
        debugName:
            'FabulariumTelegramDownload',
        errorsAreFatal:
            true,
        onError:
            errorPort.sendPort,
        onExit:
            exitPort.sendPort,
      );

      return await completer.future;
    } finally {
      await messageSubscription
          ?.cancel();

      await errorSubscription
          ?.cancel();

      await exitSubscription
          ?.cancel();

      messagePort.close();

      errorPort.close();

      exitPort.close();

      /*
       * Normalmente o worker já terminou com
       * Isolate.exit().
       *
       * Esse kill funciona apenas como
       * garantia adicional.
       */
      isolate?.kill(
        priority:
            Isolate.immediate,
      );
    }
  }
}

class TelegramDownloadWorkerException
    implements Exception {
  final String message;

  final String? stackTrace;

  const TelegramDownloadWorkerException(
    this.message, {
    this.stackTrace,
  });

  @override
  String toString() {
    return message;
  }
}

class _TelegramDownloadWorkerRequest {
  final SendPort replyPort;

  final TelegramMedia media;

  final String groupTitle;

  const _TelegramDownloadWorkerRequest({
    required this.replyPort,
    required this.media,
    required this.groupTitle,
  });
}

@pragma(
  'vm:entry-point',
)
Future<void>
    _telegramDownloadWorkerEntryPoint(
  _TelegramDownloadWorkerRequest request,
) async {
  final telegramClient =
      TelegramClient.instance;

  int lastReceived =
      0;

  int lastTotal =
      request.media.size;

  DateTime lastProgressSent =
      DateTime.fromMillisecondsSinceEpoch(
    0,
  );

  void sendProgress(
    int received,
    int total, {
    bool force = false,
  }) {
    lastReceived =
        received;

    if (total >
        0) {
      lastTotal =
          total;
    }

    final now =
        DateTime.now();

    final elapsed =
        now.difference(
      lastProgressSent,
    );

    /*
     * O worker pode processar dezenas de
     * chunks por segundo.
     *
     * Não enviamos todos para a UI.
     */
    if (!force &&
        elapsed <
            const Duration(
              milliseconds:
                  120,
            )) {
      return;
    }

    lastProgressSent =
        now;

    request.replyPort.send(
      <String, dynamic>{
        'type':
            'progress',
        'received':
            lastReceived,
        'total':
            lastTotal,
      },
    );
  }

  try {
    /*
     * Cada isolate possui seus próprios
     * singletons.
     *
     * Portanto este TelegramClient é
     * completamente separado do cliente
     * utilizado pela interface.
     */
    await telegramClient
        .connect();

    final path =
        await TelegramDownloadEngine
            .instance
            .downloadMedia(
      request.media,
      groupTitle:
          request.groupTitle,
      onProgress:
          (
        received,
        total,
      ) {
        sendProgress(
          received,
          total,
        );
      },
    );

    /*
     * Garante que a interface recebe 100%.
     */
    sendProgress(
      lastReceived,
      lastTotal,
      force:
          true,
    );

    /*
     * Fechamos todas as conexões MTProto
     * do worker antes de encerrar.
     */
    await telegramClient
        .disconnect();

    /*
     * Envia o resultado e destrói
     * completamente o isolate.
     */
    Isolate.exit(
      request.replyPort,
      <String, dynamic>{
        'type':
            'completed',
        'path':
            path,
      },
    );
  } catch (
    error,
    stackTrace
  ) {
    try {
      await telegramClient
          .disconnect();
    } catch (_) {}

    Isolate.exit(
      request.replyPort,
      <String, dynamic>{
        'type':
            'error',
        'error':
            error.toString(),
        'stackTrace':
            stackTrace.toString(),
      },
    );
  }
}