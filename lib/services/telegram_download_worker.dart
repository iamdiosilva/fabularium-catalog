import 'dart:async';
import 'dart:isolate';

import '../models/telegram_media.dart';
import 'telegram_client.dart';
import 'telegram_download_engine.dart';

typedef TelegramDownloadSessionInvalidHandler =
    FutureOr<void> Function(
  String errorMessage,
);

class TelegramDownloadWorker {
  TelegramDownloadWorker._() {
    _downloadWorker = _PersistentTelegramWorker(
      mode: _TelegramWorkerMode.download,
      onSessionInvalid: _handleWorkerSessionInvalid,
    );

    _previewWorker = _PersistentTelegramWorker(
      mode: _TelegramWorkerMode.preview,
      onSessionInvalid: _handleWorkerSessionInvalid,
    );
  }

  static final TelegramDownloadWorker instance =
      TelegramDownloadWorker._();

  late final _PersistentTelegramWorker _downloadWorker;

  late final _PersistentTelegramWorker _previewWorker;

  TelegramDownloadSessionInvalidHandler?
      _sessionInvalidHandler;

  bool _sessionInvalidNotified = false;

  bool _sessionResetting = false;

  /*
   * Tempo máximo para o download começar a
   * realmente produzir eventos de progresso.
   *
   * A primeira conexão pode precisar abrir
   * sockets, autorizar DCs e aquecer o pool,
   * então damos uma margem maior.
   */
  static const Duration _downloadStartTimeout =
      Duration(
    seconds: 90,
  );

  /*
   * Depois que o download começou, 60 segundos
   * sem qualquer evento de progresso é tratado
   * como conexão travada.
   */
  static const Duration _downloadInactivityTimeout =
      Duration(
    seconds: 60,
  );

  /*
   * Pequena pausa depois de matar o isolate para
   * permitir que o Windows libere os sockets antes
   * de criarmos um novo pool.
   */
  static const Duration _recoveryDelay =
      Duration(
    milliseconds: 500,
  );

  /*
   * Tentativa original + duas recuperações.
   */
  static const int _maxAutomaticRecoveries = 2;

  // ============================================================
  // SESSION INVALID HANDLER
  // ============================================================

  void setSessionInvalidHandler(
    TelegramDownloadSessionInvalidHandler? handler,
  ) {
    _sessionInvalidHandler = handler;
  }

  void _handleWorkerSessionInvalid(
    String errorMessage,
  ) {
    /*
     * Download e preview possuem isolates
     * independentes.
     *
     * Se ambos perceberem a sessão inválida
     * aproximadamente ao mesmo tempo,
     * notificamos o lifecycle somente uma vez.
     */
    if (_sessionInvalidNotified) {
      return;
    }

    _sessionInvalidNotified = true;

    final handler = _sessionInvalidHandler;

    if (handler == null) {
      return;
    }

    unawaited(
      Future<void>(
        () async {
          try {
            await handler(
              errorMessage,
            );
          } catch (_) {}
        },
      ),
    );
  }

  // ============================================================
  // DOWNLOAD
  // ============================================================

  Future<String> downloadMedia(
    TelegramMedia media, {
    required String groupTitle,
    void Function(
      int received,
      int total,
    )?
        onProgress,
  }) {
    return _downloadMediaWithRecovery(
      media,
      groupTitle: groupTitle,
      onProgress: onProgress,
    );
  }

  Future<String> _downloadMediaWithRecovery(
    TelegramMedia media, {
    required String groupTitle,
    void Function(
      int received,
      int total,
    )?
        onProgress,
  }) async {
    int automaticRecoveries = 0;

    while (true) {
      if (_sessionResetting) {
        throw const TelegramDownloadWorkerException(
          'Telegram session reset.',
        );
      }

      final watchdog =
          Completer<void>();

      Timer? watchdogTimer;

      bool receivedProgress =
          false;

      void armWatchdog(
        Duration duration,
      ) {
        if (watchdog.isCompleted) {
          return;
        }

        watchdogTimer?.cancel();

        watchdogTimer = Timer(
          duration,
          () {
            if (!watchdog.isCompleted) {
              watchdog.complete();
            }
          },
        );
      }

      /*
       * A primeira janela é maior porque inclui
       * criação do isolate, conexão e aquecimento
       * do pool de download.
       */
      armWatchdog(
        _downloadStartTimeout,
      );

      final attemptFuture =
          _downloadWorker.execute(
        type: 'download',
        media: media,
        groupTitle: groupTitle,
        onProgress: (
          received,
          total,
        ) {
          /*
           * Qualquer progresso recebido prova que
           * o pipeline ainda está respondendo.
           */
          receivedProgress = true;

          armWatchdog(
            _downloadInactivityTimeout,
          );

          onProgress?.call(
            received,
            total,
          );
        },
      );

      /*
       * Transformamos sucesso/erro em um valor.
       *
       * Isso é importante porque Future.any não
       * deve gerar erro não tratado se o watchdog
       * vencer e depois o reset completar o Future
       * original com erro.
       */
      final attemptResultFuture =
          attemptFuture.then<_DownloadAttemptResult>(
        (path) {
          return _DownloadAttemptResult.completed(
            path,
          );
        },
        onError: (
          Object error,
          StackTrace stackTrace,
        ) {
          return _DownloadAttemptResult.failed(
            error,
            stackTrace,
          );
        },
      );

      final watchdogResultFuture =
          watchdog.future.then<_DownloadAttemptResult>(
        (_) {
          return const _DownloadAttemptResult.stalled();
        },
      );

      late final _DownloadAttemptResult result;

      try {
        result = await Future.any(
          <Future<_DownloadAttemptResult>>[
            attemptResultFuture,
            watchdogResultFuture,
          ],
        );
      } finally {
        watchdogTimer?.cancel();
      }

      // ========================================================
      // SUCCESS
      // ========================================================

      if (result.status ==
          _DownloadAttemptStatus.completed) {
        return result.path!;
      }

      // ========================================================
      // NORMAL ERROR
      // ========================================================

      if (result.status ==
          _DownloadAttemptStatus.failed) {
        /*
         * Erros normais continuam sendo entregues
         * imediatamente para a fila.
         *
         * Não fazemos retry indiscriminado aqui,
         * pois erros como sessão inválida,
         * FILE_REFERENCE_EXPIRED etc. precisam
         * manter sua semântica original.
         */
        Error.throwWithStackTrace(
          result.error!,
          result.stackTrace ??
              StackTrace.current,
        );
      }

      // ========================================================
      // STALLED DOWNLOAD
      // ========================================================

      final inactivity =
          receivedProgress
              ? _downloadInactivityTimeout
              : _downloadStartTimeout;

      final stallError =
          TelegramDownloadStalledException(
        'Telegram download stopped responding '
        'for ${inactivity.inSeconds} seconds.',
        recoveryNumber:
            automaticRecoveries + 1,
      );

      /*
       * Aqui reproduzimos somente para o subsistema
       * de download aquilo que reiniciar o aplicativo
       * faria:
       *
       * - mata o isolate;
       * - derruba seus sockets;
       * - limpa o client daquele isolate.
       *
       * O PreviewWorker permanece vivo.
       */
      await _downloadWorker.reset(
        stallError,
      );

      /*
       * Se logout/session reset começou ao mesmo
       * tempo que o watchdog, não devemos recriar
       * o worker.
       */
      if (_sessionResetting) {
        throw const TelegramDownloadWorkerException(
          'Telegram session reset.',
        );
      }

      if (automaticRecoveries >=
          _maxAutomaticRecoveries) {
        throw TelegramDownloadStalledException(
          'Telegram download stopped responding '
          'after $_maxAutomaticRecoveries '
          'automatic recovery attempts.',
          recoveryNumber:
              automaticRecoveries,
        );
      }

      automaticRecoveries++;

      /*
       * O DownloadEngine preserva o .part e o
       * .resume.json.
       *
       * A próxima execução cria um isolate novo,
       * lê o checkpoint e continua dali.
       */
      await Future<void>.delayed(
        _recoveryDelay,
      );
    }
  }

  // ============================================================
  // PREVIEW
  // ============================================================

  Future<String> downloadPreview(
    TelegramMedia media,
  ) {
    return _previewWorker.execute(
      type: 'preview',
      media: media,
    );
  }

  // ============================================================
  // PERFORMANCE
  // ============================================================

  void setInteractiveMode(
    bool interactive,
  ) {
    _downloadWorker.setInteractiveMode(
      interactive,
    );
  }

  // ============================================================
  // SESSION RESET
  // ============================================================

  /*
   * Encerra download + preview da sessão atual,
   * mas NÃO descarta permanentemente os workers.
   *
   * Depois de um novo login, eles podem iniciar
   * novamente normalmente.
   */
  Future<void> resetSession() async {
    _sessionResetting = true;

    const reason =
        TelegramDownloadWorkerException(
      'Telegram session reset.',
    );

    try {
      await Future.wait(
        [
          _downloadWorker.reset(
            reason,
          ),
          _previewWorker.reset(
            reason,
          ),
        ],
      );
    } finally {
      _sessionInvalidNotified = false;

      _sessionResetting = false;
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  Future<void> dispose() async {
    _sessionInvalidHandler = null;

    _sessionResetting = true;

    try {
      await Future.wait(
        [
          _downloadWorker.dispose(),
          _previewWorker.dispose(),
        ],
      );
    } finally {
      _sessionResetting = false;
    }
  }
}

// ============================================================
// DOWNLOAD ATTEMPT
// ============================================================

enum _DownloadAttemptStatus {
  completed,
  failed,
  stalled,
}

class _DownloadAttemptResult {
  final _DownloadAttemptStatus status;

  final String? path;

  final Object? error;

  final StackTrace? stackTrace;

  const _DownloadAttemptResult._({
    required this.status,
    this.path,
    this.error,
    this.stackTrace,
  });

  const _DownloadAttemptResult.completed(
    String path,
  ) : this._(
          status:
              _DownloadAttemptStatus.completed,
          path:
              path,
        );

  const _DownloadAttemptResult.failed(
    Object error,
    StackTrace stackTrace,
  ) : this._(
          status:
              _DownloadAttemptStatus.failed,
          error:
              error,
          stackTrace:
              stackTrace,
        );

  const _DownloadAttemptResult.stalled()
      : this._(
          status:
              _DownloadAttemptStatus.stalled,
        );
}

// ============================================================
// WORKER MODE
// ============================================================

enum _TelegramWorkerMode {
  download,
  preview,
}

// ============================================================
// PERSISTENT WORKER
// ============================================================

class _PersistentTelegramWorker {
  final _TelegramWorkerMode mode;

  final void Function(
    String errorMessage,
  ) onSessionInvalid;

  _PersistentTelegramWorker({
    required this.mode,
    required this.onSessionInvalid,
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
  Future<void>? _resetFuture;

  Completer<void>? _readyCompleter;

  final Map<int, _PendingWorkerRequest>
      _pending =
      <int, _PendingWorkerRequest>{};

  int _nextRequestId = 0;

  bool _disposed = false;

  bool _interactiveMode = false;

  // ============================================================
  // INTERACTIVE MODE
  // ============================================================

  void setInteractiveMode(
    bool value,
  ) {
    _interactiveMode = value;

    if (mode !=
        _TelegramWorkerMode.download) {
      return;
    }

    final commandPort = _commandPort;

    if (commandPort == null) {
      return;
    }

    commandPort.send(
      <String, dynamic>{
        'type': 'interactive',
        'value': value,
      },
    );
  }

  // ============================================================
  // EXECUTE
  // ============================================================

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

    final commandPort = _commandPort;

    if (commandPort == null) {
      throw StateError(
        'Telegram worker is not available.',
      );
    }

    final requestId =
        ++_nextRequestId;

    final completer =
        Completer<String>();

    _pending[requestId] =
        _PendingWorkerRequest(
      completer: completer,
      onProgress: onProgress,
    );

    commandPort.send(
      <String, dynamic>{
        'type': type,
        'requestId': requestId,
        'media': media,
        'groupTitle': groupTitle,
      },
    );

    return completer.future;
  }

  // ============================================================
  // START
  // ============================================================

  Future<void> _ensureStarted() async {
    if (_disposed) {
      throw StateError(
        'Telegram worker has been disposed.',
      );
    }

    final resetting = _resetFuture;

    if (resetting != null) {
      await resetting;
    }

    if (_commandPort != null) {
      return;
    }

    final existing = _startFuture;

    if (existing != null) {
      await existing;

      return;
    }

    final future = _start();

    _startFuture = future;

    try {
      await future;
    } finally {
      if (identical(
        _startFuture,
        future,
      )) {
        _startFuture = null;
      }
    }
  }

  Future<void> _start() async {
    final eventPort =
        ReceivePort();

    final errorPort =
        ReceivePort();

    final exitPort =
        ReceivePort();

    _eventPort = eventPort;
    _errorPort = errorPort;
    _exitPort = exitPort;

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
      (
        dynamic error,
      ) {
        if (_disposed ||
            _resetFuture != null) {
          return;
        }

        String message =
            error.toString();

        if (error is List &&
            error.isNotEmpty) {
          message =
              error.first.toString();
        }

        if (_isInvalidTelegramSessionError(
          message,
        )) {
          _handleInvalidSession(
            message,
          );

          return;
        }

        final exception =
            TelegramDownloadWorkerException(
          message,
        );

        _failAll(
          exception,
        );

        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(
            exception,
          );
        }
      },
    );

    _exitSubscription =
        exitPort.listen(
      (_) {
        if (_disposed ||
            _resetFuture != null) {
          return;
        }

        _commandPort = null;
        _isolate = null;
        _startFuture = null;

        const exception =
            TelegramDownloadWorkerException(
          'Telegram worker stopped unexpectedly.',
        );

        _failAll(
          exception,
        );

        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(
            exception,
          );
        }
      },
    );

    try {
      _isolate =
          await Isolate.spawn<
              Map<String, dynamic>>(
        _telegramPersistentWorkerEntryPoint,
        <String, dynamic>{
          'eventPort': eventPort.sendPort,
          'mode': mode.name,
        },
        debugName:
            mode ==
                    _TelegramWorkerMode.download
                ? 'FabulariumTelegramDownloadWorker'
                : 'FabulariumTelegramPreviewWorker',
        errorsAreFatal: true,
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
      );

      await readyCompleter.future;
    } catch (_) {
      rethrow;
    }
  }

  // ============================================================
  // EVENTS
  // ============================================================

  void _handleEvent(
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

    if (type == 'ready') {
      final commandPort =
          message['commandPort'];

      if (commandPort is SendPort) {
        _commandPort =
            commandPort;

        if (mode ==
            _TelegramWorkerMode.download) {
          commandPort.send(
            <String, dynamic>{
              'type': 'interactive',
              'value':
                  _interactiveMode,
            },
          );
        }

        final ready =
            _readyCompleter;

        if (ready != null &&
            !ready.isCompleted) {
          ready.complete();
        }
      }

      return;
    }

    if (type == 'fatal') {
      if (_resetFuture != null) {
        return;
      }

      final errorMessage =
          message['error']?.toString() ??
              'Fatal Telegram worker error.';

      final stackTrace =
          message['stackTrace']?.toString();

      if (_isInvalidTelegramSessionError(
        errorMessage,
      )) {
        _handleInvalidSession(
          errorMessage,
          stackTrace: stackTrace,
        );

        return;
      }

      final error =
          TelegramDownloadWorkerException(
        errorMessage,
        stackTrace: stackTrace,
      );

      final ready =
          _readyCompleter;

      if (ready != null &&
          !ready.isCompleted) {
        ready.completeError(
          error,
        );
      }

      _failAll(
        error,
      );

      return;
    }

    final requestId =
        message['requestId'];

    if (requestId is! int) {
      return;
    }

    final pending =
        _pending[requestId];

    if (pending == null) {
      return;
    }

    if (type == 'progress') {
      final received =
          message['received'];

      final total =
          message['total'];

      if (received is int &&
          total is int) {
        pending.onProgress?.call(
          received,
          total,
        );
      }

      return;
    }

    if (type == 'completed') {
      _pending.remove(
        requestId,
      );

      final path =
          message['path'];

      if (path is String) {
        if (!pending
            .completer
            .isCompleted) {
          pending.completer.complete(
            path,
          );
        }
      } else {
        if (!pending
            .completer
            .isCompleted) {
          pending.completer.completeError(
            const TelegramDownloadWorkerException(
              'Worker completed without returning a file path.',
            ),
          );
        }
      }

      return;
    }

    if (type == 'error') {
      final errorMessage =
          message['error']?.toString() ??
              'Unknown Telegram worker error.';

      final stackTrace =
          message['stackTrace']?.toString();

      if (_isInvalidTelegramSessionError(
        errorMessage,
      )) {
        _handleInvalidSession(
          errorMessage,
          stackTrace: stackTrace,
        );

        return;
      }

      _pending.remove(
        requestId,
      );

      if (!pending
          .completer
          .isCompleted) {
        pending.completer.completeError(
          TelegramDownloadWorkerException(
            errorMessage,
            stackTrace: stackTrace,
          ),
        );
      }
    }
  }

  // ============================================================
  // INVALID SESSION
  // ============================================================

  void _handleInvalidSession(
    String errorMessage, {
    String? stackTrace,
  }) {
    if (_disposed) {
      return;
    }

    final exception =
        TelegramDownloadSessionInvalidException(
      errorMessage,
      stackTrace: stackTrace,
    );

    final ready =
        _readyCompleter;

    if (ready != null &&
        !ready.isCompleted) {
      ready.completeError(
        exception,
      );
    }

    _failAll(
      exception,
    );

    unawaited(
      reset(
        exception,
      ),
    );

    onSessionInvalid(
      errorMessage,
    );
  }

  // ============================================================
  // PENDING
  // ============================================================

  void _failAll(
    Object error,
  ) {
    final pendingRequests =
        _pending.values.toList();

    _pending.clear();

    for (final pending
        in pendingRequests) {
      if (!pending
          .completer
          .isCompleted) {
        pending.completer.completeError(
          error,
        );
      }
    }
  }

  // ============================================================
  // RESET
  // ============================================================

  Future<void> reset(
    Object reason,
  ) {
    final existing =
        _resetFuture;

    if (existing != null) {
      return existing;
    }

    late final Future<void> future;

    future =
        _performReset(
      reason,
    ).whenComplete(
      () {
        if (identical(
          _resetFuture,
          future,
        )) {
          _resetFuture = null;
        }
      },
    );

    _resetFuture = future;

    return future;
  }

  Future<void> _performReset(
    Object reason,
  ) async {
    final ready =
        _readyCompleter;

    if (ready != null &&
        !ready.isCompleted) {
      ready.completeError(
        reason,
      );
    }

    _readyCompleter = null;

    _failAll(
      reason,
    );

    final isolate =
        _isolate;

    final eventSubscription =
        _eventSubscription;

    final errorSubscription =
        _errorSubscription;

    final exitSubscription =
        _exitSubscription;

    final eventPort =
        _eventPort;

    final errorPort =
        _errorPort;

    final exitPort =
        _exitPort;

    _isolate = null;
    _commandPort = null;

    _eventSubscription = null;
    _errorSubscription = null;
    _exitSubscription = null;

    _eventPort = null;
    _errorPort = null;
    _exitPort = null;

    _startFuture = null;

    isolate?.kill(
      priority: Isolate.immediate,
    );

    await eventSubscription?.cancel();
    await errorSubscription?.cancel();
    await exitSubscription?.cancel();

    eventPort?.close();
    errorPort?.close();
    exitPort?.close();
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await _performReset(
      const TelegramDownloadWorkerException(
        'Telegram worker disposed.',
      ),
    );
  }
}

// ============================================================
// PENDING REQUEST
// ============================================================

class _PendingWorkerRequest {
  final Completer<String> completer;

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

// ============================================================
// EXCEPTIONS
// ============================================================

class TelegramDownloadWorkerException
    implements Exception {
  final String message;

  final String? stackTrace;

  const TelegramDownloadWorkerException(
    this.message, {
    this.stackTrace,
  });

  @override
  String toString() => message;
}

class TelegramDownloadSessionInvalidException
    extends TelegramDownloadWorkerException {
  const TelegramDownloadSessionInvalidException(
    super.message, {
    super.stackTrace,
  });
}

class TelegramDownloadStalledException
    extends TelegramDownloadWorkerException {
  final int recoveryNumber;

  const TelegramDownloadStalledException(
    super.message, {
    required this.recoveryNumber,
  });
}

// ============================================================
// SESSION ERROR
// ============================================================

bool _isInvalidTelegramSessionError(
  String message,
) {
  return message.contains(
        'AUTH_KEY_UNREGISTERED',
      ) ||
      message.contains(
        'AUTH_KEY_INVALID',
      ) ||
      message.contains(
        'SESSION_REVOKED',
      ) ||
      message.contains(
        'SESSION_EXPIRED',
      );
}

// ============================================================
// RUNTIME POLICY
// ============================================================

class _DownloadRuntimePolicy {
  bool interactive = false;

  int get maxInFlight =>
      interactive ? 1 : 4;

  Duration get yieldDelay =>
      interactive
          ? const Duration(
              milliseconds: 8,
            )
          : Duration.zero;
}

// ============================================================
// ISOLATE
// ============================================================

@pragma(
  'vm:entry-point',
)
Future<void> _telegramPersistentWorkerEntryPoint(
  Map<String, dynamic> bootstrap,
) async {
  final eventPort =
      bootstrap['eventPort'];

  if (eventPort is! SendPort) {
    return;
  }

  final mode =
      bootstrap['mode']?.toString();

  final commandPort =
      ReceivePort();

  final telegramClient =
      TelegramClient.instance;

  final runtimePolicy =
      _DownloadRuntimePolicy();

  Future<void>? activeDownload;

  try {
    await telegramClient.connect();

    eventPort.send(
      <String, dynamic>{
        'type': 'ready',
        'commandPort':
            commandPort.sendPort,
      },
    );

    await for (final dynamic rawCommand
        in commandPort) {
      if (rawCommand is! Map) {
        continue;
      }

      final command =
          Map<dynamic, dynamic>.from(
        rawCommand,
      );

      final type =
          command['type'];

      if (type == 'interactive') {
        runtimePolicy.interactive =
            command['value'] == true;

        continue;
      }

      if (type == 'shutdown') {
        final current =
            activeDownload;

        if (current != null) {
          try {
            await current;
          } catch (_) {}
        }

        break;
      }

      final requestId =
          command['requestId'];

      final media =
          command['media'];

      if (requestId is! int ||
          media is! TelegramMedia) {
        continue;
      }

      // ========================================================
      // DOWNLOAD
      // ========================================================

      if (mode ==
              _TelegramWorkerMode
                  .download.name &&
          type == 'download') {
        if (activeDownload != null) {
          eventPort.send(
            <String, dynamic>{
              'type': 'error',
              'requestId': requestId,
              'error':
                  'Download worker is already busy.',
            },
          );

          continue;
        }

        final operation =
            _executeDownloadCommand(
          eventPort: eventPort,
          requestId: requestId,
          media: media,
          groupTitle:
              command['groupTitle']
                      ?.toString() ??
                  'Telegram',
          runtimePolicy:
              runtimePolicy,
        );

        activeDownload = operation;

        unawaited(
          operation.whenComplete(
            () {
              activeDownload = null;
            },
          ),
        );

        continue;
      }

      // ========================================================
      // PREVIEW
      // ========================================================

      if (mode ==
              _TelegramWorkerMode
                  .preview.name &&
          type == 'preview') {
        await _executePreviewCommand(
          eventPort: eventPort,
          requestId: requestId,
          media: media,
        );
      }
    }
  } catch (
    error,
    stackTrace
  ) {
    eventPort.send(
      <String, dynamic>{
        'type': 'fatal',
        'error': error.toString(),
        'stackTrace':
            stackTrace.toString(),
      },
    );
  } finally {
    commandPort.close();

    try {
      await telegramClient.disconnect();
    } catch (_) {}
  }
}

// ============================================================
// DOWNLOAD COMMAND
// ============================================================

Future<void> _executeDownloadCommand({
  required SendPort eventPort,
  required int requestId,
  required TelegramMedia media,
  required String groupTitle,
  required _DownloadRuntimePolicy runtimePolicy,
}) async {
  int lastReceived = 0;

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
    lastReceived = received;

    if (total > 0) {
      lastTotal = total;
    }

    final now =
        DateTime.now();

    if (!force &&
        now.difference(
              lastSent,
            ) <
            const Duration(
              milliseconds: 120,
            )) {
      return;
    }

    lastSent = now;

    eventPort.send(
      <String, dynamic>{
        'type': 'progress',
        'requestId': requestId,
        'received': lastReceived,
        'total': lastTotal,
      },
    );
  }

  try {
    final path =
        await TelegramDownloadEngine
            .instance
            .downloadMedia(
      media,
      groupTitle: groupTitle,
      maxInFlightProvider: () =>
          runtimePolicy.maxInFlight,
      yieldDelayProvider: () =>
          runtimePolicy.yieldDelay,
      onProgress: (
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
      media.size > 0
          ? media.size
          : lastReceived,
      media.size > 0
          ? media.size
          : lastTotal,
      force: true,
    );

    eventPort.send(
      <String, dynamic>{
        'type': 'completed',
        'requestId': requestId,
        'path': path,
      },
    );
  } catch (
    error,
    stackTrace
  ) {
    eventPort.send(
      <String, dynamic>{
        'type': 'error',
        'requestId': requestId,
        'error': error.toString(),
        'stackTrace':
            stackTrace.toString(),
      },
    );
  }
}

// ============================================================
// PREVIEW COMMAND
// ============================================================

Future<void> _executePreviewCommand({
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
        'type': 'completed',
        'requestId': requestId,
        'path': path,
      },
    );
  } catch (
    error,
    stackTrace
  ) {
    eventPort.send(
      <String, dynamic>{
        'type': 'error',
        'requestId': requestId,
        'error': error.toString(),
        'stackTrace':
            stackTrace.toString(),
      },
    );
  }
}