import 'dart:async';
import 'dart:isolate';

import '../models/telegram_media.dart';
import 'telegram_client.dart';
import 'telegram_download_engine.dart';

class TelegramDownloadWorker {
  TelegramDownloadWorker._();

  static final TelegramDownloadWorker instance =
      TelegramDownloadWorker._();

  final _PersistentTelegramWorker
      _downloadWorker =
      _PersistentTelegramWorker(
    mode:
        _TelegramWorkerMode.download,
  );

  final _PersistentTelegramWorker
      _previewWorker =
      _PersistentTelegramWorker(
    mode:
        _TelegramWorkerMode.preview,
  );

  Future<String> downloadMedia(
    TelegramMedia media, {
    required String groupTitle,
    void Function(
      int received,
      int total,
    )?
        onProgress,
  }) {
    return _downloadWorker.execute(
      type:
          'download',
      media:
          media,
      groupTitle:
          groupTitle,
      onProgress:
          onProgress,
    );
  }

  Future<String> downloadPreview(
    TelegramMedia media,
  ) {
    return _previewWorker.execute(
      type:
          'preview',
      media:
          media,
    );
  }

  Future<void> dispose() async {
    await Future.wait(
      [
        _downloadWorker.dispose(),
        _previewWorker.dispose(),
      ],
    );
  }
}

enum _TelegramWorkerMode {
  download,
  preview,
}

class _PersistentTelegramWorker {
  final _TelegramWorkerMode mode;

  _PersistentTelegramWorker({
    required this.mode,
  });

  Isolate? _isolate;

  SendPort? _commandPort;

  ReceivePort? _eventPort;

  ReceivePort? _errorPort;

  ReceivePort? _exitPort;

  StreamSubscription<dynamic>?
      _eventSubscription;

  StreamSubscription<dynamic>?
      _errorSubscription;

  StreamSubscription<dynamic>?
      _exitSubscription;

  Future<void>? _startFuture;

  Completer<void>? _readyCompleter;

  final Map<int, _PendingWorkerRequest>
      _pending =
      {};

  int _nextRequestId =
      0;

  bool _disposed =
      false;

  Future<String> execute({
    required String type,
    required TelegramMedia media,
    String? groupTitle,
    void Function(
      int received,
      int total,
    )?
        onProgress,
  }) async {
    if (_disposed) {
      throw StateError(
        'Telegram worker has been disposed.',
      );
    }

    await _ensureStarted();

    final commandPort =
        _commandPort;

    if (commandPort == null) {
      throw StateError(
        'Telegram worker is not available.',
      );
    }

    final requestId =
        ++_nextRequestId;

    final completer =
        Completer<String>();

    _pending[
            requestId] =
        _PendingWorkerRequest(
      completer:
          completer,
      onProgress:
          onProgress,
    );

    commandPort.send(
      <String, dynamic>{
        'type':
            type,
        'requestId':
            requestId,
        'media':
            media,
        'groupTitle':
            groupTitle,
      },
    );

    return completer.future;
  }

  Future<void> _ensureStarted() {
    if (_commandPort != null) {
      return Future<void>.value();
    }

    final existing =
        _startFuture;

    if (existing != null) {
      return existing;
    }

    final future =
        _start();

    _startFuture =
        future;

    return future;
  }

  Future<void> _start() async {
    final eventPort =
        ReceivePort();

    final errorPort =
        ReceivePort();

    final exitPort =
        ReceivePort();

    _eventPort =
        eventPort;

    _errorPort =
        errorPort;

    _exitPort =
        exitPort;

    final readyCompleter =
        Completer<void>();

    _readyCompleter =
        readyCompleter;

    _eventSubscription =
        eventPort.listen(
      _handleEvent,
    );

    _errorSubscription =
        errorPort.listen(
      (dynamic error) {
        String message =
            error.toString();

        if (error is List &&
            error.isNotEmpty) {
          message =
              error.first.toString();
        }

        _failAll(
          TelegramDownloadWorkerException(
            message,
          ),
        );

        if (!readyCompleter
            .isCompleted) {
          readyCompleter
              .completeError(
            TelegramDownloadWorkerException(
              message,
            ),
          );
        }
      },
    );

    _exitSubscription =
        exitPort.listen(
      (_) {
        _commandPort =
            null;

        _isolate =
            null;

        _startFuture =
            null;

        if (!_disposed) {
          _failAll(
            const TelegramDownloadWorkerException(
              'Telegram worker stopped unexpectedly.',
            ),
          );

          if (!readyCompleter
              .isCompleted) {
            readyCompleter
                .completeError(
              const TelegramDownloadWorkerException(
                'Telegram worker stopped during initialization.',
              ),
            );
          }
        }
      },
    );

    try {
      _isolate =
          await Isolate.spawn<
              Map<String, dynamic>>(
        _telegramPersistentWorkerEntryPoint,
        <String, dynamic>{
          'eventPort':
              eventPort.sendPort,
          'mode':
              mode.name,
        },
        debugName:
            mode ==
                    _TelegramWorkerMode
                        .download
                ? 'FabulariumTelegramDownloadWorker'
                : 'FabulariumTelegramPreviewWorker',
        errorsAreFatal:
            true,
        onError:
            errorPort.sendPort,
        onExit:
            exitPort.sendPort,
      );

      await readyCompleter.future;
    } catch (_) {
      _startFuture =
          null;

      rethrow;
    }
  }

  void _handleEvent(
    dynamic rawMessage,
  ) {
    if (rawMessage
        is! Map) {
      return;
    }

    final message =
        Map<dynamic, dynamic>.from(
      rawMessage,
    );

    final type =
        message['type'];

    if (type ==
        'ready') {
      final commandPort =
          message[
              'commandPort'];

      if (commandPort
          is SendPort) {
        _commandPort =
            commandPort;

        final readyCompleter =
            _readyCompleter;

        if (readyCompleter !=
                null &&
            !readyCompleter
                .isCompleted) {
          readyCompleter
              .complete();
        }
      }

      return;
    }

    if (type ==
        'fatal') {
      final error =
          TelegramDownloadWorkerException(
        message['error']
                ?.toString() ??
            'Fatal Telegram worker error.',
        stackTrace:
            message[
                    'stackTrace']
                ?.toString(),
      );

      final readyCompleter =
          _readyCompleter;

      if (readyCompleter !=
              null &&
          !readyCompleter
              .isCompleted) {
        readyCompleter
            .completeError(
          error,
        );
      }

      _failAll(
        error,
      );

      return;
    }

    final requestId =
        message[
            'requestId'];

    if (requestId
        is! int) {
      return;
    }

    final pending =
        _pending[
            requestId];

    if (pending ==
        null) {
      return;
    }

    if (type ==
        'progress') {
      final received =
          message[
              'received'];

      final total =
          message[
              'total'];

      if (received is int &&
          total is int) {
        pending
            .onProgress
            ?.call(
          received,
          total,
        );
      }

      return;
    }

    if (type ==
        'completed') {
      _pending.remove(
        requestId,
      );

      final path =
          message[
              'path'];

      if (path is String) {
        if (!pending
            .completer
            .isCompleted) {
          pending
              .completer
              .complete(
            path,
          );
        }
      } else {
        if (!pending
            .completer
            .isCompleted) {
          pending
              .completer
              .completeError(
            const TelegramDownloadWorkerException(
              'Worker completed without returning a file path.',
            ),
          );
        }
      }

      return;
    }

    if (type ==
        'error') {
      _pending.remove(
        requestId,
      );

      if (!pending
          .completer
          .isCompleted) {
        pending
            .completer
            .completeError(
          TelegramDownloadWorkerException(
            message['error']
                    ?.toString() ??
                'Unknown Telegram worker error.',
            stackTrace:
                message[
                        'stackTrace']
                    ?.toString(),
          ),
        );
      }
    }
  }

  void _failAll(
    Object error,
  ) {
    final pendingRequests =
        _pending.values
            .toList();

    _pending.clear();

    for (final pending
        in pendingRequests) {
      if (!pending
          .completer
          .isCompleted) {
        pending
            .completer
            .completeError(
          error,
        );
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed =
        true;

    _commandPort?.send(
      <String, dynamic>{
        'type':
            'shutdown',
      },
    );

    await Future<void>.delayed(
      const Duration(
        milliseconds:
            100,
      ),
    );

    _isolate?.kill(
      priority:
          Isolate.immediate,
    );

    _isolate =
        null;

    _commandPort =
        null;

    _failAll(
      const TelegramDownloadWorkerException(
        'Telegram worker disposed.',
      ),
    );

    await _eventSubscription
        ?.cancel();

    await _errorSubscription
        ?.cancel();

    await _exitSubscription
        ?.cancel();

    _eventPort?.close();

    _errorPort?.close();

    _exitPort?.close();

    _eventPort =
        null;

    _errorPort =
        null;

    _exitPort =
        null;
  }
}

class _PendingWorkerRequest {
  final Completer<String>
      completer;

  final void Function(
    int received,
    int total,
  )?
      onProgress;

  const _PendingWorkerRequest({
    required this.completer,
    required this.onProgress,
  });
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
  String toString() =>
      message;
}

@pragma(
  'vm:entry-point',
)
Future<void>
    _telegramPersistentWorkerEntryPoint(
  Map<String, dynamic> bootstrap,
) async {
  final eventPort =
      bootstrap[
          'eventPort'];

  if (eventPort
      is! SendPort) {
    return;
  }

  final mode =
      bootstrap[
              'mode']
          ?.toString();

  final commandPort =
      ReceivePort();

  final telegramClient =
      TelegramClient.instance;

  try {
    /*
     * A conexão é aberta apenas uma vez.
     *
     * Como o isolate permanece vivo,
     * os DCs e pools permanecem aquecidos.
     */
    await telegramClient
        .connect();

    eventPort.send(
      <String, dynamic>{
        'type':
            'ready',
        'commandPort':
            commandPort.sendPort,
      },
    );

    await for (final dynamic rawCommand
        in commandPort) {
      if (rawCommand
          is! Map) {
        continue;
      }

      final command =
          Map<dynamic, dynamic>.from(
        rawCommand,
      );

      final type =
          command[
              'type'];

      if (type ==
          'shutdown') {
        break;
      }

      final requestId =
          command[
              'requestId'];

      final media =
          command[
              'media'];

      if (requestId
              is! int ||
          media
              is! TelegramMedia) {
        continue;
      }

      if (mode ==
              _TelegramWorkerMode
                  .download.name &&
          type ==
              'download') {
        await _executeDownloadCommand(
          eventPort:
              eventPort,
          requestId:
              requestId,
          media:
              media,
          groupTitle:
              command[
                      'groupTitle']
                  ?.toString() ??
                  'Telegram',
        );

        continue;
      }

      if (mode ==
              _TelegramWorkerMode
                  .preview.name &&
          type ==
              'preview') {
        await _executePreviewCommand(
          eventPort:
              eventPort,
          requestId:
              requestId,
          media:
              media,
        );
      }
    }
  } catch (
    error,
    stackTrace
  ) {
    eventPort.send(
      <String, dynamic>{
        'type':
            'fatal',
        'error':
            error.toString(),
        'stackTrace':
            stackTrace.toString(),
      },
    );
  } finally {
    commandPort.close();

    try {
      await telegramClient
          .disconnect();
    } catch (_) {}
  }
}

Future<void>
    _executeDownloadCommand({
  required SendPort eventPort,
  required int requestId,
  required TelegramMedia media,
  required String groupTitle,
}) async {
  int lastReceived =
      0;

  int lastTotal =
      media.size;

  DateTime lastSent =
      DateTime.fromMillisecondsSinceEpoch(
    0,
  );

  void progress(
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

    if (!force &&
        now.difference(
              lastSent,
            ) <
            const Duration(
              milliseconds:
                  120,
            )) {
      return;
    }

    lastSent =
        now;

    eventPort.send(
      <String, dynamic>{
        'type':
            'progress',
        'requestId':
            requestId,
        'received':
            lastReceived,
        'total':
            lastTotal,
      },
    );
  }

  try {
    final path =
        await TelegramDownloadEngine
            .instance
            .downloadMedia(
      media,
      groupTitle:
          groupTitle,
      onProgress:
          (
        received,
        total,
      ) {
        progress(
          received,
          total,
        );
      },
    );

    progress(
      media.size >
              0
          ? media.size
          : lastReceived,
      media.size >
              0
          ? media.size
          : lastTotal,
      force:
          true,
    );

    eventPort.send(
      <String, dynamic>{
        'type':
            'completed',
        'requestId':
            requestId,
        'path':
            path,
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
        'requestId':
            requestId,
        'error':
            error.toString(),
        'stackTrace':
            stackTrace.toString(),
      },
    );
  }
}

Future<void>
    _executePreviewCommand({
  required SendPort eventPort,
  required int requestId,
  required TelegramMedia media,
}) async {
  try {
    final path =
        await TelegramDownloadEngine
            .instance
            .downloadPreview(
      media,
    );

    eventPort.send(
      <String, dynamic>{
        'type':
            'completed',
        'requestId':
            requestId,
        'path':
            path,
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
        'requestId':
            requestId,
        'error':
            error.toString(),
        'stackTrace':
            stackTrace.toString(),
      },
    );
  }
}