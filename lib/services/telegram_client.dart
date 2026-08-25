import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:t/t.dart' as t;
import 'package:tg/tg.dart' as tg;

import '../config/telegram_config.dart';
import 'telegram_socket.dart';

class TelegramClient {
  TelegramClient._();

  static final TelegramClient instance =
      TelegramClient._();

  static const String _sessionFileName =
      'telegram_auth.json';

  tg.Client? _client;
  TelegramSocket? _socket;

  Future<tg.Client>? _connectFuture;
  Future<void>? _disconnectFuture;

  t.DcOption _dc = const t.DcOption(
    ipv6: false,
    mediaOnly: false,
    tcpoOnly: false,
    cdn: false,
    static: false,
    thisPortOnly: false,
    id: 1,
    ipAddress: '149.154.167.50',
    port: 443,
  );

  final List<t.DcOption> dcs = [];

  final Map<int, tg.Client> _dcClients = {};
  final Map<int, TelegramSocket> _dcSockets = {};
  final Map<int, Future<tg.Client>>
      _dcClientFutures = {};

  final Map<String, tg.Client>
      _downloadClients = {};

  final Map<String, TelegramSocket>
      _downloadSockets = {};

  final Map<String, Future<tg.Client>>
      _downloadClientFutures = {};

  tg.Client? get client =>
      _client;

  bool get hasSavedSession {
    try {
      return _resolveSessionFile(
        migrateLegacy: true,
      ).existsSync();
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // SESSION PATH
  // ============================================================

  String _sessionFilePath() {
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
      _sessionFileName,
    );
  }

  File _resolveSessionFile({
    required bool migrateLegacy,
  }) {
    final target =
        File(
      _sessionFilePath(),
    );

    if (!migrateLegacy ||
        target.existsSync()) {
      return target;
    }

    /*
     * Versões anteriores gravavam a sessão
     * no current working directory.
     *
     * Fazemos a migração de forma idempotente,
     * para funcionar mesmo com vários isolates.
     */
    final legacy =
        File(
      p.join(
        Directory.current.path,
        _sessionFileName,
      ),
    );

    if (!legacy.existsSync()) {
      return target;
    }

    try {
      target.parent.createSync(
        recursive: true,
      );

      if (!target.existsSync()) {
        legacy.copySync(
          target.path,
        );
      }

      /*
       * Só removemos o arquivo antigo depois
       * de confirmar que o novo realmente existe.
       */
      if (target.existsSync() &&
          legacy.existsSync()) {
        try {
          legacy.deleteSync();
        } catch (_) {}
      }
    } catch (_) {
      /*
       * Se houver uma corrida entre isolates,
       * outro isolate pode já ter concluído
       * a migração. Nesse caso basta usar o
       * arquivo novo se ele existir.
       */
    }

    return target.existsSync()
        ? target
        : legacy;
  }

  // ============================================================
  // MAIN CONNECTION
  // ============================================================

  Future<tg.Client> connect() {
    final existingClient =
        _client;

    if (existingClient != null) {
      return Future<tg.Client>.value(
        existingClient,
      );
    }

    final existingFuture =
        _connectFuture;

    if (existingFuture != null) {
      return existingFuture;
    }

    late final Future<tg.Client>
        future;

    future =
        _connectInternal()
            .whenComplete(
      () {
        if (identical(
          _connectFuture,
          future,
        )) {
          _connectFuture =
              null;
        }
      },
    );

    _connectFuture =
        future;

    return future;
  }

  Future<tg.Client>
      _connectInternal() async {
    /*
     * Se um disconnect anterior ainda está
     * terminando, esperamos antes de abrir
     * outro socket.
     */
    final disconnectFuture =
        _disconnectFuture;

    if (disconnectFuture != null) {
      await disconnectFuture;
    }

    final session =
        _loadSession();

    final savedAuthorizationKey =
        session?.authorizationKey;

    if (session != null) {
      _dc =
          session.dc;
    }

    final rawSocket =
        await Socket.connect(
      _dc.ipAddress,
      _dc.port,
      timeout:
          const Duration(
        seconds: 15,
      ),
    );

    final telegramSocket =
        TelegramSocket(
      rawSocket,
    );

    _socket =
        telegramSocket;

    try {
      final obfuscation =
          tg.Obfuscation.random(
        false,
        _dc.id,
      );

      final idGenerator =
          tg.MessageIdGenerator();

      await telegramSocket.send(
        obfuscation.preamble,
      );

      late final tg.AuthorizationKey
          authorizationKey;

      if (savedAuthorizationKey !=
          null) {
        authorizationKey =
            savedAuthorizationKey;
      } else {
        authorizationKey =
            await tg.Client.authorize(
          telegramSocket,
          obfuscation,
          idGenerator,
        );
      }

      final client =
          tg.Client(
        socket:
            telegramSocket,
        obfuscation:
            obfuscation,
        authorizationKey:
            authorizationKey,
        idGenerator:
            idGenerator,
      );

      /*
       * Mantemos o stream drenado, mas sem
       * converter cada update/evento para
       * String e sem enviar para StreamController.
       */
      _drainClientStream(
        client,
      );

      final configResponse =
          await client
              .initConnection<t.Config>(
        apiId:
            TelegramConfig.apiId,
        deviceModel:
            'Fabularium Catalog',
        systemVersion:
            'Windows',
        appVersion:
            '1.0.0',
        systemLangCode:
            'pt-br',
        langPack:
            '',
        langCode:
            'pt-br',
        query:
            const t.HelpGetConfig(),
      );

      if (configResponse.error !=
          null) {
        throw Exception(
          configResponse
              .error!
              .errorMessage,
        );
      }

      final config =
          configResponse.result;

      if (config != null) {
        dcs
          ..clear()
          ..addAll(
            config.dcOptions
                .whereType<
                    t.DcOption>(),
          );
      }

      _client =
          client;

      return client;
    } catch (_) {
      try {
        await telegramSocket.close();
      } catch (_) {}

      if (identical(
        _socket,
        telegramSocket,
      )) {
        _socket =
            null;
      }

      rethrow;
    }
  }

  // ============================================================
  // AUTHORIZED DC CLIENT
  // ============================================================

  Future<tg.Client>
      getClientForDataCenter(
    int dcId,
  ) async {
    final mainClient =
        _client;

    if (mainClient == null) {
      throw StateError(
        'Cliente Telegram principal não conectado.',
      );
    }

    if (dcId == _dc.id) {
      return mainClient;
    }

    final cached =
        _dcClients[dcId];

    if (cached != null) {
      return cached;
    }

    final pending =
        _dcClientFutures[dcId];

    if (pending != null) {
      return pending;
    }

    final future =
        _createAuthorizedDataCenterClient(
      dcId,
    );

    _dcClientFutures[dcId] =
        future;

    try {
      final result =
          await future;

      /*
       * Se a conexão principal foi encerrada
       * enquanto o DC estava sendo criado,
       * não deixamos o cliente auxiliar
       * sobreviver escondido.
       */
      if (_client == null) {
        final socket =
            _dcSockets.remove(
          dcId,
        );

        try {
          await socket?.close();
        } catch (_) {}

        throw StateError(
          'Cliente Telegram foi desconectado durante a autorização do DC $dcId.',
        );
      }

      _dcClients[dcId] =
          result;

      return result;
    } finally {
      _dcClientFutures.remove(
        dcId,
      );
    }
  }

  Future<tg.Client>
      _createAuthorizedDataCenterClient(
    int dcId,
  ) async {
    final mainClient =
        _client;

    if (mainClient == null) {
      throw StateError(
        'Cliente Telegram principal não conectado.',
      );
    }

    final dc =
        findDataCenter(
      dcId,
    );

    if (dc == null) {
      throw StateError(
        'Telegram DC $dcId não encontrado.',
      );
    }

    const maxAttempts =
        2;

    Object? lastError;

    for (int attempt = 1;
        attempt <= maxAttempts;
        attempt++) {
      final exportResponse =
          await mainClient.auth
              .exportAuthorization(
        dcId: dcId,
      );

      if (exportResponse.error !=
          null) {
        throw Exception(
          'Falha exportando autorização '
          'para DC $dcId: '
          '${exportResponse.error!.errorMessage}',
        );
      }

      final dynamic exported =
          exportResponse.result;

      if (exported == null) {
        throw Exception(
          'Telegram não retornou '
          'autorização exportada '
          'para DC $dcId.',
        );
      }

      late final int exportedId;

      late final Uint8List
          exportedBytes;

      try {
        exportedId =
            exported.id as int;

        final dynamic rawBytes =
            exported.bytes;

        if (rawBytes
            is Uint8List) {
          exportedBytes =
              Uint8List.fromList(
            rawBytes,
          );
        } else {
          exportedBytes =
              Uint8List.fromList(
            List<int>.from(
              rawBytes as List,
            ),
          );
        }
      } catch (e) {
        throw Exception(
          'Falha lendo autorização '
          'do DC $dcId: $e',
        );
      }

      try {
        final connection =
            await _openImportedAuthorizationConnection(
          dc: dc,
          exportedId:
              exportedId,
          exportedBytes:
              exportedBytes,
        );

        _dcSockets[dcId] =
            connection.socket;

        return connection.client;
      } catch (e) {
        lastError =
            e;

        final message =
            e.toString();

        if (message.contains(
              'AUTH_BYTES_INVALID',
            ) &&
            attempt <
                maxAttempts) {
          continue;
        }

        rethrow;
      }
    }

    throw Exception(
      'Não foi possível autorizar '
      'o DC $dcId: $lastError',
    );
  }

  // ============================================================
  // DOWNLOAD CONNECTION POOL
  // ============================================================

  Future<void> warmDownloadPool(
    int dcId, {
    int size = 4,
  }) async {
    await getClientForDataCenter(
      dcId,
    );

    await Future.wait(
      List.generate(
        size,
        (slot) =>
            getDownloadClientForDataCenter(
          dcId,
          slot,
        ),
      ),
    );
  }

  Future<tg.Client>
      getDownloadClientForDataCenter(
    int dcId,
    int slot,
  ) async {
    final key =
        '$dcId:$slot';

    final cached =
        _downloadClients[key];

    if (cached != null) {
      return cached;
    }

    final pending =
        _downloadClientFutures[key];

    if (pending != null) {
      return pending;
    }

    final future =
        _createDownloadSession(
      dcId: dcId,
      slot: slot,
    );

    _downloadClientFutures[key] =
        future;

    try {
      final result =
          await future;

      if (_client == null) {
        final socket =
            _downloadSockets.remove(
          key,
        );

        try {
          await socket?.close();
        } catch (_) {}

        throw StateError(
          'Cliente Telegram foi desconectado durante a criação da sessão de download.',
        );
      }

      _downloadClients[key] =
          result;

      return result;
    } finally {
      _downloadClientFutures.remove(
        key,
      );
    }
  }

  Future<tg.Client>
      _createDownloadSession({
    required int dcId,
    required int slot,
  }) async {
    final authorizedClient =
        await getClientForDataCenter(
      dcId,
    );

    final clonedAuthorizationKey =
        tg.AuthorizationKey.fromJson(
      authorizedClient
          .authorizationKey
          .toJson(),
    );

    final dc =
        findMediaDataCenter(
              dcId,
            ) ??
            findDataCenter(
              dcId,
            ) ??
            (dcId == _dc.id
                ? _dc
                : null);

    if (dc == null) {
      throw StateError(
        'Endpoint do DC $dcId não encontrado.',
      );
    }

    final connection =
        await _openConnectionWithAuthorizationKey(
      dc: dc,
      authorizationKey:
          clonedAuthorizationKey,
    );

    final key =
        '$dcId:$slot';

    _downloadSockets[key] =
        connection.socket;

    return connection.client;
  }

  // ============================================================
  // OPEN IMPORTED DC CONNECTION
  // ============================================================

  Future<_TelegramConnection>
      _openImportedAuthorizationConnection({
    required t.DcOption dc,
    required int exportedId,
    required Uint8List exportedBytes,
  }) async {
    final rawSocket =
        await Socket.connect(
      dc.ipAddress,
      dc.port,
      timeout:
          const Duration(
        seconds: 15,
      ),
    );

    final telegramSocket =
        TelegramSocket(
      rawSocket,
    );

    try {
      final obfuscation =
          tg.Obfuscation.random(
        false,
        dc.id,
      );

      final idGenerator =
          tg.MessageIdGenerator();

      await telegramSocket.send(
        obfuscation.preamble,
      );

      final authorizationKey =
          await tg.Client.authorize(
        telegramSocket,
        obfuscation,
        idGenerator,
      );

      final client =
          tg.Client(
        socket:
            telegramSocket,
        obfuscation:
            obfuscation,
        authorizationKey:
            authorizationKey,
        idGenerator:
            idGenerator,
      );

      _drainClientStream(
        client,
      );

      /*
       * ImportAuthorization permanece como
       * a PRIMEIRA chamada API dessa sessão.
       *
       * Essa ordem é necessária para evitar
       * AUTH_BYTES_INVALID em alguns DCs.
       */
      final importResponse =
          await client.initConnection<
              t.AuthAuthorizationBase>(
        apiId:
            TelegramConfig.apiId,
        deviceModel:
            'Fabularium Catalog',
        systemVersion:
            'Windows',
        appVersion:
            '1.0.0',
        systemLangCode:
            'pt-br',
        langPack:
            '',
        langCode:
            'pt-br',
        query:
            t.AuthImportAuthorization(
          id:
              exportedId,
          bytes:
              exportedBytes,
        ),
      );

      if (importResponse.error !=
          null) {
        throw Exception(
          'Falha importando autorização '
          'no DC ${dc.id}: '
          '${importResponse.error!.errorMessage}',
        );
      }

      if (importResponse.result ==
          null) {
        throw Exception(
          'Telegram não confirmou '
          'a autorização do DC ${dc.id}.',
        );
      }

      return _TelegramConnection(
        client:
            client,
        socket:
            telegramSocket,
      );
    } catch (_) {
      try {
        await telegramSocket.close();
      } catch (_) {}

      rethrow;
    }
  }

  // ============================================================
  // OPEN EXISTING AUTH KEY CONNECTION
  // ============================================================

  Future<_TelegramConnection>
      _openConnectionWithAuthorizationKey({
    required t.DcOption dc,
    required tg.AuthorizationKey
        authorizationKey,
  }) async {
    final rawSocket =
        await Socket.connect(
      dc.ipAddress,
      dc.port,
      timeout:
          const Duration(
        seconds: 15,
      ),
    );

    final telegramSocket =
        TelegramSocket(
      rawSocket,
    );

    try {
      final obfuscation =
          tg.Obfuscation.random(
        false,
        dc.id,
      );

      final idGenerator =
          tg.MessageIdGenerator();

      await telegramSocket.send(
        obfuscation.preamble,
      );

      final client =
          tg.Client(
        socket:
            telegramSocket,
        obfuscation:
            obfuscation,
        authorizationKey:
            authorizationKey,
        idGenerator:
            idGenerator,
      );

      _drainClientStream(
        client,
      );

      await _initializeClient(
        client,
      );

      return _TelegramConnection(
        client:
            client,
        socket:
            telegramSocket,
      );
    } catch (_) {
      try {
        await telegramSocket.close();
      } catch (_) {}

      rethrow;
    }
  }

  void _drainClientStream(
    tg.Client client,
  ) {
    /*
     * Antes cada evento fazia:
     *
     * event.toString()
     * + interpolação
     * + StreamController.add()
     *
     * para um stream que não possuía
     * consumidores no aplicativo.
     *
     * Mantemos somente um listener vazio
     * para drenar updates/erros do tg.Client.
     */
    client.stream.listen(
      (_) {},
      onError:
          (_) {},
    );
  }

  Future<void> _initializeClient(
    tg.Client client,
  ) async {
    final response =
        await client
            .initConnection<t.Config>(
      apiId:
          TelegramConfig.apiId,
      deviceModel:
          'Fabularium Catalog',
      systemVersion:
          'Windows',
      appVersion:
          '1.0.0',
      systemLangCode:
          'pt-br',
      langPack:
          '',
      langCode:
          'pt-br',
      query:
          const t.HelpGetConfig(),
    );

    if (response.error !=
        null) {
      throw Exception(
        response
            .error!
            .errorMessage,
      );
    }
  }

  // ============================================================
  // DATA CENTERS
  // ============================================================

  t.DcOption? findDataCenter(
    int id,
  ) {
    t.DcOption? fallback;

    for (final dc in dcs) {
      if (dc.id != id) {
        continue;
      }

      if (dc.ipv6 ||
          dc.cdn ||
          dc.mediaOnly) {
        continue;
      }

      fallback ??=
          dc;

      if (!dc.tcpoOnly) {
        return dc;
      }
    }

    return fallback;
  }

  t.DcOption?
      findMediaDataCenter(
    int id,
  ) {
    t.DcOption? fallback;

    for (final dc in dcs) {
      if (dc.id != id) {
        continue;
      }

      if (dc.ipv6 ||
          dc.cdn ||
          !dc.mediaOnly) {
        continue;
      }

      fallback ??=
          dc;

      if (!dc.tcpoOnly) {
        return dc;
      }
    }

    return fallback;
  }

  // ============================================================
  // SESSION
  // ============================================================

  Future<void> saveSession() async {
    final client =
        _client;

    if (client == null) {
      return;
    }

    final data =
        <String, dynamic>{
      'dc': {
        'id':
            _dc.id,
        'ipAddress':
            _dc.ipAddress,
        'port':
            _dc.port,
      },
      'authorizationKey':
          client
              .authorizationKey
              .toJson(),
    };

    final file =
        File(
      _sessionFilePath(),
    );

    await file.parent.create(
      recursive: true,
    );

    /*
     * Grava primeiro em arquivo temporário
     * e depois renomeia.
     *
     * Evita deixar telegram_auth.json
     * parcialmente escrito se o processo
     * for encerrado no meio da gravação.
     */
    final temp =
        File(
      '${file.path}.tmp',
    );

    await temp.writeAsString(
      jsonEncode(
        data,
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

    /*
     * Se ainda existir uma sessão legada,
     * removemos depois que a nova foi salva.
     */
    final legacy =
        File(
      p.join(
        Directory.current.path,
        _sessionFileName,
      ),
    );

    if (legacy.path !=
            file.path &&
        await legacy.exists()) {
      try {
        await legacy.delete();
      } catch (_) {}
    }
  }

  _TelegramSession?
      _loadSession() {
    try {
      final file =
          _resolveSessionFile(
        migrateLegacy: true,
      );

      if (!file.existsSync()) {
        return null;
      }

      final decoded =
          jsonDecode(
        file.readAsStringSync(),
      );

      if (decoded
          is! Map<String, dynamic>) {
        return null;
      }

      final authData =
          decoded[
              'authorizationKey'];

      final dcData =
          decoded[
              'dc'];

      if (authData
              is! Map<String, dynamic> ||
          dcData
              is! Map<String, dynamic>) {
        return null;
      }

      final authorizationKey =
          tg.AuthorizationKey.fromJson(
        authData,
      );

      final dc =
          t.DcOption(
        ipv6:
            false,
        mediaOnly:
            false,
        tcpoOnly:
            false,
        cdn:
            false,
        static:
            false,
        thisPortOnly:
            false,
        id:
            dcData['id']
                as int,
        ipAddress:
            dcData['ipAddress']
                as String,
        port:
            dcData['port']
                as int,
      );

      return _TelegramSession(
        authorizationKey:
            authorizationKey,
        dc:
            dc,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteSession() async {
    final primary =
        File(
      _sessionFilePath(),
    );

    final legacy =
        File(
      p.join(
        Directory.current.path,
        _sessionFileName,
      ),
    );

    final temp =
        File(
      '${primary.path}.tmp',
    );

    for (final file in <File>[
      primary,
      legacy,
      temp,
    ]) {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  // ============================================================
  // CHANGE MAIN DC
  // ============================================================

  Future<void> changeDataCenter(
    t.DcOption dc,
  ) async {
    await _disconnectInternal(
      closeMain: true,
    );

    _dc =
        dc;
  }

  // ============================================================
  // DISCONNECT
  // ============================================================

  Future<void>
      _disconnectAuxiliaryClients() async {
    /*
     * Esperamos autorizações que já estavam
     * em andamento antes de fechar os sockets.
     *
     * Isso evita um Future concluir depois do
     * disconnect e registrar um socket órfão.
     */
    final pending =
        _dcClientFutures.values
            .toList();

    if (pending.isNotEmpty) {
      await Future.wait(
        pending.map(
          (future) async {
            try {
              await future;
            } catch (_) {}
          },
        ),
      );
    }

    final sockets =
        _dcSockets.values.toList();

    _dcClients.clear();
    _dcSockets.clear();
    _dcClientFutures.clear();

    await Future.wait(
      sockets.map(
        (socket) async {
          try {
            await socket.close();
          } catch (_) {}
        },
      ),
    );
  }

  Future<void>
      _disconnectDownloadClients() async {
    final pending =
        _downloadClientFutures.values
            .toList();

    if (pending.isNotEmpty) {
      await Future.wait(
        pending.map(
          (future) async {
            try {
              await future;
            } catch (_) {}
          },
        ),
      );
    }

    final sockets =
        _downloadSockets.values
            .toList();

    _downloadClients.clear();
    _downloadSockets.clear();
    _downloadClientFutures.clear();

    await Future.wait(
      sockets.map(
        (socket) async {
          try {
            await socket.close();
          } catch (_) {}
        },
      ),
    );
  }

  Future<void> _disconnectInternal({
    required bool closeMain,
  }) async {
    /*
     * Download clients podem depender de
     * um cliente auxiliar, então fechamos
     * o pool antes dos DCs auxiliares.
     */
    await _disconnectDownloadClients();
    await _disconnectAuxiliaryClients();

    if (closeMain) {
      final socket =
          _socket;

      _socket =
          null;

      _client =
          null;

      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  Future<void> disconnect() {
    final existing =
        _disconnectFuture;

    if (existing != null) {
      return existing;
    }

    late final Future<void>
        future;

    future =
        _disconnectInternal(
      closeMain: true,
    ).whenComplete(
      () {
        if (identical(
          _disconnectFuture,
          future,
        )) {
          _disconnectFuture =
              null;
        }
      },
    );

    _disconnectFuture =
        future;

    return future;
  }

  Future<void> dispose() async {
    await disconnect();
  }
}

class _TelegramConnection {
  final tg.Client client;
  final TelegramSocket socket;

  const _TelegramConnection({
    required this.client,
    required this.socket,
  });
}

class _TelegramSession {
  final tg.AuthorizationKey
      authorizationKey;

  final t.DcOption dc;

  const _TelegramSession({
    required this.authorizationKey,
    required this.dc,
  });
}