import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:t/t.dart' as t;

import '../models/telegram_group.dart';
import '../models/telegram_message.dart';
import 'telegram_client.dart';
import 'telegram_service.dart';

typedef TelegramSessionInvalidHandler =
    FutureOr<void> Function(
  String errorMessage,
);

class TelegramBrowseWorker {
  TelegramBrowseWorker._();

  static final TelegramBrowseWorker instance =
      TelegramBrowseWorker._();

  static const Duration _requestTimeout =
      Duration(
    seconds: 20,
  );

  static const int _maxCachedMessageGroups =
      15;

  List<TelegramGroup>? _groupsCache;

  Future<List<TelegramGroup>>?
      _groupsInFlight;

  final LinkedHashMap<
      String,
      List<TelegramMessage>> _messagesCache =
      LinkedHashMap<
          String,
          List<TelegramMessage>>();

  final Map<
      String,
      Future<List<TelegramMessage>>>
      _messagesInFlight =
      <String,
          Future<List<TelegramMessage>>>{};

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

  final Map<int, _PendingGroupsRequest>
      _pendingGroups =
      <int, _PendingGroupsRequest>{};

  final Map<int, _PendingMessagesRequest>
      _pendingMessages =
      <int, _PendingMessagesRequest>{};

  int _nextRequestId = 0;

  bool _disposed = false;

  TelegramSessionInvalidHandler?
      _sessionInvalidHandler;

  bool _sessionInvalidNotified = false;

  // ============================================================
  // SESSION INVALID HANDLER
  // ============================================================

  void setSessionInvalidHandler(
    TelegramSessionInvalidHandler? handler,
  ) {
    _sessionInvalidHandler =
        handler;
  }

  bool _isInvalidSessionError(
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

  void _notifySessionInvalid(
    String errorMessage,
  ) {
    if (_sessionInvalidNotified) {
      return;
    }

    _sessionInvalidNotified =
        true;

    final exception =
        TelegramSessionInvalidException(
      errorMessage,
    );

    /*
     * Derruba imediatamente este worker.
     *
     * Também limpamos os caches porque eles
     * pertencem à sessão que acabou de se
     * tornar inválida.
     */
    unawaited(
      reset(
        reason: exception,
        clearCache: true,
      ),
    );

    final handler =
        _sessionInvalidHandler;

    if (handler == null) {
      return;
    }

    /*
     * Executamos o callback fora da pilha
     * atual do ReceivePort.
     *
     * Isso evita reentrância enquanto ainda
     * estamos terminando de processar a
     * resposta que detectou a sessão inválida.
     */
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
  // GROUPS
  // ============================================================

  Future<List<TelegramGroup>> getGroups({
    bool forceRefresh = false,
  }) {
    if (!forceRefresh) {
      final cached =
          _groupsCache;

      if (cached != null) {
        return Future<
            List<TelegramGroup>>.value(
          List<TelegramGroup>.from(
            cached,
          ),
        );
      }
    }

    final existing =
        _groupsInFlight;

    if (existing != null) {
      return existing;
    }

    late final Future<List<TelegramGroup>>
        future;

    future = _executeGroups().then(
      (
        groups,
      ) {
        _groupsCache =
            List<TelegramGroup>.from(
          groups,
        );

        return List<TelegramGroup>.from(
          groups,
        );
      },
    ).whenComplete(
      () {
        if (identical(
          _groupsInFlight,
          future,
        )) {
          _groupsInFlight =
              null;
        }
      },
    );

    _groupsInFlight =
        future;

    return future;
  }

  void clearGroupsCache() {
    _groupsCache =
        null;
  }

  // ============================================================
  // MESSAGES
  // ============================================================

  Future<List<TelegramMessage>> getMessages(
    TelegramGroup group, {
    int limit = 50,
    bool forceRefresh = false,
  }) {
    final key =
        _messagesCacheKey(
      group,
      limit,
    );

    if (!forceRefresh) {
      final cached =
          _messagesCache.remove(
        key,
      );

      if (cached != null) {
        /*
         * Remove + insere novamente para marcar
         * este grupo como o mais recentemente usado.
         */
        _messagesCache[key] =
            cached;

        return Future<
            List<TelegramMessage>>.value(
          List<TelegramMessage>.from(
            cached,
          ),
        );
      }
    }

    final existing =
        _messagesInFlight[key];

    if (existing != null) {
      return existing;
    }

    late final Future<List<TelegramMessage>>
        future;

    future = _executeMessages(
      group: group,
      limit: limit,
    ).then(
      (
        messages,
      ) {
        _storeMessages(
          key,
          messages,
        );

        return List<TelegramMessage>.from(
          messages,
        );
      },
    ).whenComplete(
      () {
        final current =
            _messagesInFlight[key];

        if (identical(
          current,
          future,
        )) {
          _messagesInFlight.remove(
            key,
          );
        }
      },
    );

    _messagesInFlight[key] =
        future;

    return future;
  }

  void clearGroupMessages(
    TelegramGroup group,
  ) {
    final prefix =
        '${_groupKey(group)}|';

    final keys =
        _messagesCache.keys
            .where(
              (key) =>
                  key.startsWith(
                prefix,
              ),
            )
            .toList();

    for (final key in keys) {
      _messagesCache.remove(
        key,
      );
    }
  }

  void clearMessagesCache() {
    _messagesCache.clear();
  }

  void clearCaches() {
    clearGroupsCache();
    clearMessagesCache();
  }

  void _storeMessages(
    String key,
    List<TelegramMessage> messages,
  ) {
    _messagesCache.remove(
      key,
    );

    _messagesCache[key] =
        List<TelegramMessage>.from(
      messages,
    );

    while (_messagesCache.length >
        _maxCachedMessageGroups) {
      final oldestKey =
          _messagesCache.keys.first;

      _messagesCache.remove(
        oldestKey,
      );
    }
  }

  // ============================================================
  // REQUESTS
  // ============================================================

  Future<List<TelegramGroup>>
      _executeGroups() async {
    await _ensureStarted();

    final commandPort =
        _commandPort;

    if (commandPort == null) {
      throw StateError(
        'Telegram browse worker unavailable.',
      );
    }

    final requestId =
        ++_nextRequestId;

    final completer =
        Completer<List<TelegramGroup>>();

    final timeout =
        Timer(
      _requestTimeout,
      () {
        final pending =
            _pendingGroups.remove(
          requestId,
        );

        if (pending == null ||
            pending.completer.isCompleted) {
          return;
        }

        final error =
            TimeoutException(
          'Telegram demorou demais para carregar os grupos.',
          _requestTimeout,
        );

        pending.completer.completeError(
          error,
        );

        _scheduleReset(
          error,
        );
      },
    );

    _pendingGroups[requestId] =
        _PendingGroupsRequest(
      completer:
          completer,
      timeout:
          timeout,
    );

    commandPort.send(
      <String, dynamic>{
        'type':
            'groups',
        'requestId':
            requestId,
      },
    );

    return completer.future;
  }

  Future<List<TelegramMessage>>
      _executeMessages({
    required TelegramGroup group,
    required int limit,
  }) async {
    await _ensureStarted();

    final commandPort =
        _commandPort;

    if (commandPort == null) {
      throw StateError(
        'Telegram browse worker unavailable.',
      );
    }

    final requestId =
        ++_nextRequestId;

    final completer =
        Completer<List<TelegramMessage>>();

    final timeout =
        Timer(
      _requestTimeout,
      () {
        final pending =
            _pendingMessages.remove(
          requestId,
        );

        if (pending == null ||
            pending.completer.isCompleted) {
          return;
        }

        final error =
            TimeoutException(
          'Telegram demorou demais para carregar as mensagens.',
          _requestTimeout,
        );

        pending.completer.completeError(
          error,
        );

        /*
         * Se uma chamada travar,
         * descartamos o isolate/socket.
         *
         * A próxima chamada cria uma
         * conexão limpa automaticamente.
         */
        _scheduleReset(
          error,
        );
      },
    );

    _pendingMessages[requestId] =
        _PendingMessagesRequest(
      completer:
          completer,
      timeout:
          timeout,
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
  // WORKER START
  // ============================================================

  Future<void> _ensureStarted() async {
    if (_disposed) {
      throw StateError(
        'TelegramBrowseWorker disposed.',
      );
    }

    final resetFuture =
        _resetFuture;

    if (resetFuture != null) {
      await resetFuture;
    }

    if (_commandPort != null) {
      return;
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

    try {
      await future;
    } catch (_) {
      if (identical(
        _startFuture,
        future,
      )) {
        _startFuture =
            null;
      }

      rethrow;
    }
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

        if (_isInvalidSessionError(
          message,
        )) {
          _notifySessionInvalid(
            message,
          );

          return;
        }

        _scheduleReset(
          Exception(
            message,
          ),
        );
      },
    );

    _exitSubscription =
        exitPort.listen(
      (_) {
        if (_disposed ||
            _resetFuture != null) {
          return;
        }

        _scheduleReset(
          Exception(
            'Telegram browse worker stopped unexpectedly.',
          ),
        );
      },
    );

    try {
      _isolate =
          await Isolate.spawn<SendPort>(
        _telegramBrowseWorkerEntryPoint,
        eventPort.sendPort,
        debugName:
            'FabulariumTelegramBrowseWorker',
        errorsAreFatal:
            true,
        onError:
            errorPort.sendPort,
        onExit:
            exitPort.sendPort,
      );

      await readyCompleter.future;
    } catch (error) {
      if (_isInvalidSessionError(
        error.toString(),
      )) {
        _notifySessionInvalid(
          error.toString(),
        );
      } else {
        _scheduleReset(
          error,
        );
      }

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

        /*
         * Uma nova conexão foi estabelecida.
         *
         * Permitimos que uma futura sessão
         * inválida seja reportada novamente.
         */
        _sessionInvalidNotified =
            false;

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
      final errorMessage =
          message['error']?.toString() ??
              'Telegram browse worker fatal error.';

      if (_isInvalidSessionError(
        errorMessage,
      )) {
        _notifySessionInvalid(
          errorMessage,
        );

        return;
      }

      _scheduleReset(
        Exception(
          errorMessage,
        ),
      );

      return;
    }

    final requestId =
        message['requestId'];

    if (requestId is! int) {
      return;
    }

    if (type == 'groupsCompleted' ||
        type == 'groupsError') {
      _handleGroupsResponse(
        requestId,
        type,
        message,
      );

      return;
    }

    if (type == 'messagesCompleted' ||
        type == 'messagesError') {
      _handleMessagesResponse(
        requestId,
        type,
        message,
      );
    }
  }

  void _handleGroupsResponse(
    int requestId,
    dynamic type,
    Map<dynamic, dynamic> message,
  ) {
    final pending =
        _pendingGroups.remove(
      requestId,
    );

    if (pending == null) {
      return;
    }

    pending.timeout.cancel();

    if (type == 'groupsError') {
      final errorMessage =
          message['error']?.toString() ??
              'Erro ao carregar grupos.';

      if (_isInvalidSessionError(
        errorMessage,
      )) {
        final exception =
            TelegramSessionInvalidException(
          errorMessage,
        );

        /*
         * Primeiro finalizamos o Future
         * da tela que fez esta chamada.
         */
        if (!pending.completer.isCompleted) {
          pending.completer.completeError(
            exception,
          );
        }

        /*
         * Depois propagamos a invalidação
         * para o main isolate.
         */
        _notifySessionInvalid(
          errorMessage,
        );

        return;
      }

      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          Exception(
            errorMessage,
          ),
        );
      }

      return;
    }

    final rawGroups =
        message['groups'];

    if (rawGroups is! List) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          Exception(
            'Resposta inválida ao carregar grupos.',
          ),
        );
      }

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

    if (!pending.completer.isCompleted) {
      pending.completer.complete(
        groups,
      );
    }
  }

  void _handleMessagesResponse(
    int requestId,
    dynamic type,
    Map<dynamic, dynamic> message,
  ) {
    final pending =
        _pendingMessages.remove(
      requestId,
    );

    if (pending == null) {
      return;
    }

    pending.timeout.cancel();

    if (type == 'messagesError') {
      final errorMessage =
          message['error']?.toString() ??
              'Erro ao carregar mensagens.';

      if (_isInvalidSessionError(
        errorMessage,
      )) {
        final exception =
            TelegramSessionInvalidException(
          errorMessage,
        );

        if (!pending.completer.isCompleted) {
          pending.completer.completeError(
            exception,
          );
        }

        _notifySessionInvalid(
          errorMessage,
        );

        return;
      }

      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          Exception(
            errorMessage,
          ),
        );
      }

      return;
    }

    final rawMessages =
        message['messages'];

    if (rawMessages is! List) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          Exception(
            'Resposta inválida ao carregar mensagens.',
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

    if (!pending.completer.isCompleted) {
      pending.completer.complete(
        messages,
      );
    }
  }

  // ============================================================
  // RESET / RECOVERY
  // ============================================================

  void _scheduleReset(
    Object reason,
  ) {
    unawaited(
      reset(
        reason:
            reason,
      ),
    );
  }

  Future<void> reset({
    Object? reason,
    bool clearCache = false,
  }) {
    final existing =
        _resetFuture;

    if (existing != null) {
      return existing;
    }

    late final Future<void>
        future;

    future = _performReset(
      reason:
          reason ??
              const TelegramBrowseWorkerResetException(),
      clearCache:
          clearCache,
    ).whenComplete(
      () {
        if (identical(
          _resetFuture,
          future,
        )) {
          _resetFuture =
              null;
        }
      },
    );

    _resetFuture =
        future;

    return future;
  }

  Future<void> _performReset({
    required Object reason,
    required bool clearCache,
  }) async {
    if (clearCache) {
      clearCaches();
    }

    final ready =
        _readyCompleter;

    if (ready != null &&
        !ready.isCompleted) {
      ready.completeError(
        reason,
      );
    }

    _readyCompleter =
        null;

    _failAllPending(
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

    _isolate =
        null;

    _commandPort =
        null;

    _eventSubscription =
        null;

    _errorSubscription =
        null;

    _exitSubscription =
        null;

    _eventPort =
        null;

    _errorPort =
        null;

    _exitPort =
        null;

    _startFuture =
        null;

    isolate?.kill(
      priority:
          Isolate.immediate,
    );

    await eventSubscription?.cancel();
    await errorSubscription?.cancel();
    await exitSubscription?.cancel();

    eventPort?.close();
    errorPort?.close();
    exitPort?.close();
  }

  void _failAllPending(
    Object error,
  ) {
    final groups =
        _pendingGroups.values.toList();

    _pendingGroups.clear();

    for (final request
        in groups) {
      request.timeout.cancel();

      if (!request.completer.isCompleted) {
        request.completer.completeError(
          error,
        );
      }
    }

    final messages =
        _pendingMessages.values.toList();

    _pendingMessages.clear();

    for (final request
        in messages) {
      request.timeout.cancel();

      if (!request.completer.isCompleted) {
        request.completer.completeError(
          error,
        );
      }
    }
  }

  // ============================================================
  // CACHE KEYS
  // ============================================================

  String _groupKey(
    TelegramGroup group,
  ) {
    return '${group.isChannel ? 'channel' : 'chat'}'
        ':${group.id}';
  }

  String _messagesCacheKey(
    TelegramGroup group,
    int limit,
  ) {
    return '${_groupKey(group)}|limit:$limit';
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

    _sessionInvalidHandler =
        null;

    _commandPort?.send(
      <String, dynamic>{
        'type':
            'shutdown',
      },
    );

    await Future<void>.delayed(
      const Duration(
        milliseconds: 150,
      ),
    );

    await reset(
      reason:
          StateError(
        'Telegram browse worker disposed.',
      ),
      clearCache:
          true,
    );
  }
}

class TelegramBrowseWorkerResetException
    implements Exception {
  const TelegramBrowseWorkerResetException();

  @override
  String toString() =>
      'Telegram browse worker reset.';
}

class TelegramSessionInvalidException
    implements Exception {
  final String errorMessage;

  const TelegramSessionInvalidException(
    this.errorMessage,
  );

  @override
  String toString() =>
      'Telegram session invalid: $errorMessage';
}

class _PendingGroupsRequest {
  final Completer<List<TelegramGroup>>
      completer;

  final Timer timeout;

  const _PendingGroupsRequest({
    required this.completer,
    required this.timeout,
  });
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
Future<void> _telegramBrowseWorkerEntryPoint(
  SendPort eventPort,
) async {
  final commandPort =
      ReceivePort();

  final telegramClient =
      TelegramClient.instance;

  try {
    final client =
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

      final requestId =
          command['requestId'];

      if (requestId is! int) {
        continue;
      }

      if (type == 'groups') {
        try {
          final groups =
              await _loadGroups(
            client,
          );

          eventPort.send(
            <String, dynamic>{
              'type':
                  'groupsCompleted',
              'requestId':
                  requestId,
              'groups':
                  groups,
            },
          );
        } catch (
          error,
          stackTrace
        ) {
          eventPort.send(
            <String, dynamic>{
              'type':
                  'groupsError',
              'requestId':
                  requestId,
              'error':
                  error.toString(),
              'stackTrace':
                  stackTrace.toString(),
            },
          );
        }

        continue;
      }

      if (type == 'messages') {
        final group =
            command['group'];

        final limit =
            command['limit'];

        if (group is! TelegramGroup ||
            limit is! int) {
          eventPort.send(
            <String, dynamic>{
              'type':
                  'messagesError',
              'requestId':
                  requestId,
              'error':
                  'Invalid messages request.',
            },
          );

          continue;
        }

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
                  'messagesCompleted',
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
                  'messagesError',
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
      await telegramClient.disconnect();
    } catch (_) {}
  }
}

Future<List<Map<String, dynamic>>>
    _loadGroups(
  dynamic client,
) async {
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
    return <Map<String, dynamic>>[];
  }

  final dynamic data =
      result;

  List<dynamic> chats =
      <dynamic>[];

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

    if (runtimeType == 'Chat') {
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

    if (runtimeType !=
        'Channel') {
      continue;
    }

    bool megagroup =
        false;

    bool gigagroup =
        false;

    try {
      megagroup =
          chat.megagroup == true;
    } catch (_) {}

    try {
      gigagroup =
          chat.gigagroup == true;
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

  return groups;
}