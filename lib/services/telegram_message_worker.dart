import 'dart:async';
import 'dart:isolate';

import '../models/telegram_group.dart';
import '../models/telegram_message.dart';
import 'telegram_client.dart';
import 'telegram_service.dart';

class TelegramMessagesWorker {
  TelegramMessagesWorker._();

  static final TelegramMessagesWorker instance =
      TelegramMessagesWorker._();

  final Map<String, List<TelegramMessage>> _cache =
      {};

  final Map<String, Future<List<TelegramMessage>>> _inFlight =
      {};

  Isolate? _isolate;

  SendPort? _commandPort;

  ReceivePort? _eventPort;

  ReceivePort? _errorPort;

  ReceivePort? _exitPort;

  StreamSubscription<dynamic>? _eventSubscription;

  StreamSubscription<dynamic>? _errorSubscription;

  StreamSubscription<dynamic>? _exitSubscription;

  Future<void>? _startFuture;

  Completer<void>? _readyCompleter;

  final Map<int, _PendingMessagesRequest> _pending =
      {};

  int _nextRequestId =
      0;

  bool _disposed =
      false;

  static const Duration _requestTimeout =
      Duration(
    seconds: 20,
  );

  // ============================================================
  // PUBLIC
  // ============================================================

  Future<List<TelegramMessage>> getMessages(
    TelegramGroup group, {
    int limit = 50,
    bool forceRefresh = false,
  }) {
    final key =
        _groupKey(
      group,
    );

    if (!forceRefresh) {
      final cached =
          _cache[key];

      if (cached != null) {
        return Future<List<TelegramMessage>>.value(
          List<TelegramMessage>.from(
            cached,
          ),
        );
      }

      final existing =
          _inFlight[key];

      if (existing != null) {
        return existing;
      }
    }

    final future =
        _execute(
      group:
          group,
      limit:
          limit,
    ).then(
      (
        messages,
      ) {
        _cache[key] =
            List<TelegramMessage>.from(
          messages,
        );

        return List<TelegramMessage>.from(
          messages,
        );
      },
    ).whenComplete(
      () {
        _inFlight.remove(
          key,
        );
      },
    );

    _inFlight[key] =
        future;

    return future;
  }

  void clearGroup(
    TelegramGroup group,
  ) {
    _cache.remove(
      _groupKey(
        group,
      ),
    );
  }

  void clearCache() {
    _cache.clear();
  }

  // ============================================================
  // EXECUTE
  // ============================================================

  Future<List<TelegramMessage>> _execute({
    required TelegramGroup group,
    required int limit,
  }) async {
    if (_disposed) {
      throw StateError(
        'TelegramMessagesWorker disposed.',
      );
    }

    await _ensureStarted();

    final commandPort =
        _commandPort;

    if (commandPort == null) {
      throw StateError(
        'Telegram messages worker unavailable.',
      );
    }

    final requestId =
        ++_nextRequestId;

    final completer =
        Completer<List<TelegramMessage>>();

    final timer =
        Timer(
      _requestTimeout,
      () {
        final pending =
            _pending.remove(
          requestId,
        );

        if (pending == null ||
            pending.completer.isCompleted) {
          return;
        }

        pending.completer.completeError(
          TimeoutException(
            'Telegram demorou demais para responder.',
            _requestTimeout,
          ),
        );

        /*
         * IMPORTANTE:
         *
         * NÃO matamos o isolate.
         * NÃO fechamos o socket.
         *
         * Apenas abandonamos essa resposta
         * específica.
         */
      },
    );

    _pending[requestId] =
        _PendingMessagesRequest(
      completer:
          completer,
      timeout:
          timer,
    );

    commandPort.send(
      <String, dynamic>{
        'type':
            'messages',
        'requestId':
            requestId,
        'group':
            group,
        'limit':
            limit,
      },
    );

    return completer.future;
  }

  // ============================================================
  // START WORKER
  // ============================================================

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
      (
        dynamic error,
      ) {
        String message =
            error.toString();

        if (error is List &&
            error.isNotEmpty) {
          message =
              error.first.toString();
        }

        _handleWorkerFailure(
          Exception(
            message,
          ),
        );
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
          _handleWorkerFailure(
            Exception(
              'Telegram messages worker '
              'stopped unexpectedly.',
            ),
          );
        }
      },
    );

    try {
      _isolate =
          await Isolate.spawn<SendPort>(
        _telegramMessagesPersistentEntryPoint,
        eventPort.sendPort,
        debugName:
            'FabulariumTelegramMessagesWorker',
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
      final port =
          message['commandPort'];

      if (port is SendPort) {
        _commandPort =
            port;

        final completer =
            _readyCompleter;

        if (completer != null &&
            !completer.isCompleted) {
          completer.complete();
        }
      }

      return;
    }

    if (type == 'fatal') {
      _handleWorkerFailure(
        Exception(
          message['error']?.toString() ??
              'Telegram worker fatal error.',
        ),
      );

      return;
    }

    final requestId =
        message['requestId'];

    if (requestId is! int) {
      return;
    }

    final pending =
        _pending.remove(
      requestId,
    );

    /*
     * Pode ter acontecido timeout.
     *
     * Nesse caso simplesmente ignoramos
     * a resposta tardia.
     */
    if (pending == null) {
      return;
    }

    pending.timeout.cancel();

    if (type == 'completed') {
      final rawMessages =
          message['messages'];

      if (rawMessages is! List) {
        if (!pending
            .completer
            .isCompleted) {
          pending.completer.completeError(
            Exception(
              'Resposta inválida do worker.',
            ),
          );
        }

        return;
      }

      final messages =
          <TelegramMessage>[];

      for (final dynamic raw
          in rawMessages) {
        if (raw is TelegramMessage) {
          messages.add(
            raw,
          );
        }
      }

      if (!pending
          .completer
          .isCompleted) {
        pending.completer.complete(
          messages,
        );
      }

      return;
    }

    if (type == 'error') {
      if (!pending
          .completer
          .isCompleted) {
        pending.completer.completeError(
          Exception(
            message['error']?.toString() ??
                'Erro carregando mensagens.',
          ),
        );
      }
    }
  }

  void _handleWorkerFailure(
    Object error,
  ) {
    final ready =
        _readyCompleter;

    if (ready != null &&
        !ready.isCompleted) {
      ready.completeError(
        error,
      );
    }

    final pending =
        _pending.values.toList();

    _pending.clear();

    for (final request in pending) {
      request.timeout.cancel();

      if (!request
          .completer
          .isCompleted) {
        request.completer.completeError(
          error,
        );
      }
    }
  }

  String _groupKey(
    TelegramGroup group,
  ) {
    return '${group.isChannel ? 'channel' : 'chat'}'
        ':${group.id}';
  }

  // ============================================================
  // APP SHUTDOWN ONLY
  // ============================================================

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

    /*
     * Esse dispose é para o encerramento
     * do aplicativo, NÃO para navegação.
     */
    await Future<void>.delayed(
      const Duration(
        milliseconds: 250,
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

    final pending =
        _pending.values.toList();

    _pending.clear();

    for (final request in pending) {
      request.timeout.cancel();

      if (!request
          .completer
          .isCompleted) {
        request.completer.completeError(
          StateError(
            'Telegram messages worker disposed.',
          ),
        );
      }
    }

    await _eventSubscription
        ?.cancel();

    await _errorSubscription
        ?.cancel();

    await _exitSubscription
        ?.cancel();

    _eventPort?.close();
    _errorPort?.close();
    _exitPort?.close();
  }
}

class _PendingMessagesRequest {
  final Completer<List<TelegramMessage>>
      completer;

  final Timer timeout;

  const _PendingMessagesRequest({
    required this.completer,
    required this.timeout,
  });
}

// ============================================================
// ISOLATE
// ============================================================

@pragma(
  'vm:entry-point',
)
Future<void>
    _telegramMessagesPersistentEntryPoint(
  SendPort eventPort,
) async {
  final commandPort =
      ReceivePort();

  final telegramClient =
      TelegramClient.instance;

  try {
    /*
     * CONECTA UMA ÚNICA VEZ.
     *
     * Abrir/fechar páginas não interfere
     * mais nesta conexão.
     */
    await telegramClient.connect();

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
      if (rawCommand is! Map) {
        continue;
      }

      final command =
          Map<dynamic, dynamic>.from(
        rawCommand,
      );

      final type =
          command['type'];

      if (type == 'shutdown') {
        break;
      }

      if (type != 'messages') {
        continue;
      }

      final requestId =
          command['requestId'];

      final group =
          command['group'];

      final limit =
          command['limit'];

      if (requestId is! int ||
          group is! TelegramGroup ||
          limit is! int) {
        continue;
      }

      /*
       * IMPORTANTE:
       *
       * Um erro de UMA requisição não mata
       * o worker inteiro.
       */
      try {
        final messages =
            await TelegramService
                .instance
                .getMessages(
          group,
          limit:
              limit,
        );

        eventPort.send(
          <String, dynamic>{
            'type':
                'completed',
            'requestId':
                requestId,
            'messages':
                messages,
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
  } catch (
    error,
    stackTrace
  ) {
    /*
     * Somente erro da conexão/worker em si
     * é fatal.
     */
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
      await telegramClient.disconnect();
    } catch (_) {}
  }
}