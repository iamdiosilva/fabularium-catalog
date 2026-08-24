import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  /*
   * Cliente autorizado base de cada DC.
   *
   * Exemplo:
   *
   * DC principal -> sessão principal
   * DC 2        -> autorização importada UMA VEZ
   */
  final Map<int, tg.Client> _dcClients =
      {};

  final Map<int, TelegramSocket>
      _dcSockets =
      {};

  final Map<int, Future<tg.Client>>
      _dcClientFutures =
      {};

  /*
   * Pool dedicado de downloads.
   *
   * Cada entrada usa:
   *
   * mesma AuthorizationKey do DC
   * +
   * socket próprio
   * +
   * session_id próprio
   *
   * Exemplo:
   *
   * 2:0
   * 2:1
   * 2:2
   * 2:3
   */
  final Map<String, tg.Client>
      _downloadClients =
      {};

  final Map<String, TelegramSocket>
      _downloadSockets =
      {};

  final Map<String, Future<tg.Client>>
      _downloadClientFutures =
      {};

  final StreamController<Object>
      _logsController =
      StreamController<Object>.broadcast();

  Stream<Object> get logs =>
      _logsController.stream;

  tg.Client? get client =>
      _client;

  int get currentDcId =>
      _dc.id;

  bool get hasSavedSession =>
      File(_sessionFileName).existsSync();

  void _log(
    Object value,
  ) {
    if (!_logsController.isClosed) {
      _logsController.add(
        value,
      );
    }
  }

  // ============================================================
  // MAIN CONNECTION
  // ============================================================

  Future<tg.Client> connect() async {
    final existingClient =
        _client;

    if (existingClient != null) {
      return existingClient;
    }

    final session =
        _loadSession();

    final savedAuthorizationKey =
        session?.authorizationKey;

    if (session != null) {
      _dc =
          session.dc;

      _log(
        'Sessão encontrada no DC ${_dc.id}.',
      );
    }

    _log(
      'Conectando ao Telegram '
      'DC ${_dc.id} - '
      '${_dc.ipAddress}:${_dc.port}',
    );

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

    if (savedAuthorizationKey != null) {
      authorizationKey =
          savedAuthorizationKey;

      _log(
        'AuthorizationKey principal restaurada.',
      );
    } else {
      _log(
        'Criando AuthorizationKey principal...',
      );

      authorizationKey =
          await tg.Client.authorize(
        telegramSocket,
        obfuscation,
        idGenerator,
      );

      _log(
        'AuthorizationKey principal criada.',
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

    final mainDcId =
        _dc.id;

    client.stream.listen(
      (event) {
        _log(
          '[MAIN DC $mainDcId] $event',
        );
      },
      onError: (error) {
        _log(
          '[MAIN DC $mainDcId] '
          'Erro: $error',
        );
      },
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

    if (configResponse.error != null) {
      try {
        await telegramSocket.close();
      } catch (_) {}

      _socket =
          null;

      throw Exception(
        configResponse
            .error!
            .errorMessage,
      );
    }

    final config =
        configResponse.result;

    if (config != null) {
      dcs.clear();

      dcs.addAll(
        config.dcOptions
            .whereType<t.DcOption>(),
      );

      _log(
        '${dcs.length} endpoints Telegram encontrados.',
      );

      for (final dc
          in dcs) {
        _log(
          'DC ${dc.id} '
          '${dc.ipAddress}:${dc.port} '
          'mediaOnly=${dc.mediaOnly} '
          'cdn=${dc.cdn}',
        );
      }
    }

    _client =
        client;

    _log(
      'Telegram conectado no DC $mainDcId.',
    );

    return client;
  }

  // ============================================================
  // AUTHORIZED DC CLIENT
  // ============================================================

  /*
   * Retorna UMA conexão autorizada para
   * determinado DC.
   *
   * O export/import ocorre uma única vez.
   *
   * Depois os clientes paralelos de mídia
   * reutilizam a AuthorizationKey deste cliente.
   */
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

    /*
     * Já estamos no DC correto.
     */
    if (dcId ==
        _dc.id) {
      return mainClient;
    }

    /*
     * DC já autorizado.
     */
    final cached =
        _dcClients[
            dcId];

    if (cached != null) {
      return cached;
    }

    /*
     * Outro código já está autorizando
     * esse DC.
     */
    final pending =
        _dcClientFutures[
            dcId];

    if (pending != null) {
      return pending;
    }

    final future =
        _createAuthorizedDataCenterClient(
      dcId,
    );

    _dcClientFutures[
            dcId] =
        future;

    try {
      final result =
          await future;

      _dcClients[
              dcId] =
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

    _log(
      'Autorizando DC $dcId...',
    );

    /*
     * IMPORTANTE:
     *
     * Este export acontece UMA VEZ.
     */
    final exportResponse =
        await mainClient.auth
            .exportAuthorization(
      dcId:
          dcId,
    );

    if (exportResponse.error != null) {
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

    late final Uint8List exportedBytes;

    try {
      exportedId =
          exported.id
              as int;

      final dynamic rawBytes =
          exported.bytes;

      if (rawBytes is Uint8List) {
        exportedBytes =
            rawBytes;
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

    /*
     * Criamos uma nova auth_key MTProto
     * no DC de destino.
     */
    final connection =
        await _openFreshConnection(
      dc:
          dc,
      label:
          'AUTH DC $dcId',
    );

    try {
      /*
       * IMPORTANTE:
       *
       * Também acontece UMA ÚNICA VEZ.
       */
      final importResponse =
          await connection.client.auth
              .importAuthorization(
        id:
            exportedId,
        bytes:
            exportedBytes,
      );

      if (importResponse.error != null) {
        throw Exception(
          'Falha importando autorização '
          'no DC $dcId: '
          '${importResponse.error!.errorMessage}',
        );
      }

      _dcSockets[
              dcId] =
          connection.socket;

      _log(
        'DC $dcId autorizado.',
      );

      return connection.client;
    } catch (_) {
      try {
        await connection.socket.close();
      } catch (_) {}

      rethrow;
    }
  }

  // ============================================================
  // DOWNLOAD CONNECTION POOL
  // ============================================================

  Future<void> warmDownloadPool(
    int dcId, {
    int size = 4,
  }) async {
    /*
     * PRIMEIRO garante que o DC está
     * autorizado.
     *
     * Assim somente uma importAuthorization
     * será feita.
     */
    await getClientForDataCenter(
      dcId,
    );

    /*
     * Só depois criamos as sessões paralelas.
     */
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
        _downloadClients[
            key];

    if (cached != null) {
      return cached;
    }

    final pending =
        _downloadClientFutures[
            key];

    if (pending != null) {
      return pending;
    }

    final future =
        _createDownloadSession(
      dcId:
          dcId,
      slot:
          slot,
    );

    _downloadClientFutures[
            key] =
        future;

    try {
      final result =
          await future;

      _downloadClients[
              key] =
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
    /*
     * Aqui está a correção do
     * AUTH_BYTES_INVALID.
     *
     * Pegamos o cliente que JÁ FOI
     * autorizado naquele DC.
     */
    final authorizedClient =
        await getClientForDataCenter(
      dcId,
    );

    /*
     * Copiamos a MESMA AuthorizationKey.
     *
     * Não fazemos:
     *
     * exportAuthorization
     * importAuthorization
     *
     * novamente.
     */
    final clonedAuthorizationKey =
        tg.AuthorizationKey
            .fromJson(
      authorizedClient
          .authorizationKey
          .toJson(),
    );

    /*
     * Para download preferimos os endpoints
     * mediaOnly que o Telegram fornece.
     */
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
        'Endpoint do DC $dcId '
        'não encontrado.',
      );
    }

    final label =
        'DOWNLOAD DC $dcId SLOT $slot';

    _log(
      '$label usando '
      '${dc.mediaOnly ? 'media DC' : 'normal DC'} '
      '${dc.ipAddress}:${dc.port}',
    );

    final connection =
        await _openConnectionWithAuthorizationKey(
      dc:
          dc,
      authorizationKey:
          clonedAuthorizationKey,
      label:
          label,
    );

    final key =
        '$dcId:$slot';

    _downloadSockets[
            key] =
        connection.socket;

    return connection.client;
  }

  // ============================================================
  // OPEN CONNECTION
  // ============================================================

  /*
   * Nova conexão com NOVA auth_key.
   *
   * Usado somente para autorizar um DC
   * pela primeira vez.
   */
  Future<_TelegramConnection>
      _openFreshConnection({
    required t.DcOption dc,
    required String label,
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

      _log(
        '$label criando auth_key...',
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

      _listenClient(
        client,
        label,
      );

      await _initializeClient(
        client,
        label,
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

  /*
   * Nova sessão usando uma auth_key
   * JÁ AUTORIZADA.
   *
   * Esse método NÃO chama
   * tg.Client.authorize().
   *
   * Ele também NÃO faz
   * auth.importAuthorization().
   */
  Future<_TelegramConnection>
      _openConnectionWithAuthorizationKey({
    required t.DcOption dc,
    required tg.AuthorizationKey
        authorizationKey,
    required String label,
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

      _listenClient(
        client,
        label,
      );

      await _initializeClient(
        client,
        label,
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

  void _listenClient(
    tg.Client client,
    String label,
  ) {
    client.stream.listen(
      (event) {
        _log(
          '[$label] $event',
        );
      },
      onError: (error) {
        _log(
          '[$label] Erro: $error',
        );
      },
    );
  }

  Future<void> _initializeClient(
    tg.Client client,
    String label,
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

    if (response.error != null) {
      throw Exception(
        '$label: '
        '${response.error!.errorMessage}',
      );
    }
  }

  // ============================================================
  // DATA CENTERS
  // ============================================================

  /*
   * Endpoint normal.
   *
   * Usado para:
   *
   * export/import authorization
   * chamadas RPC comuns
   */
  t.DcOption? findDataCenter(
    int id,
  ) {
    t.DcOption?
        fallback;

    for (final dc
        in dcs) {
      if (dc.id !=
          id) {
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

  /*
   * Endpoint dedicado de mídia.
   *
   * É o que queremos usar para
   * upload.getFile.
   */
  t.DcOption?
      findMediaDataCenter(
    int id,
  ) {
    t.DcOption?
        fallback;

    for (final dc
        in dcs) {
      if (dc.id !=
          id) {
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
      _sessionFileName,
    );

    await file.writeAsString(
      jsonEncode(
        data,
      ),
      flush:
          true,
    );

    _log(
      'Sessão principal salva.',
    );
  }

  _TelegramSession?
      _loadSession() {
    try {
      final file =
          File(
        _sessionFileName,
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

      if (!decoded.containsKey(
        'authorizationKey',
      )) {
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
          tg.AuthorizationKey
              .fromJson(
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
            dcData[
                    'id']
                as int,
        ipAddress:
            dcData[
                    'ipAddress']
                as String,
        port:
            dcData[
                    'port']
                as int,
      );

      return _TelegramSession(
        authorizationKey:
            authorizationKey,
        dc:
            dc,
      );
    } catch (e) {
      _log(
        'Erro carregando sessão: $e',
      );

      return null;
    }
  }

  Future<void> deleteSession() async {
    final file =
        File(
      _sessionFileName,
    );

    if (await file.exists()) {
      await file.delete();
    }

    _log(
      'Sessão removida.',
    );
  }

  // ============================================================
  // CHANGE MAIN DC
  // ============================================================

  Future<void> changeDataCenter(
    t.DcOption dc,
  ) async {
    _log(
      'Alterando DC principal '
      '${_dc.id} -> ${dc.id}.',
    );

    await _disconnectAuxiliaryClients();

    await _disconnectDownloadClients();

    try {
      await _socket?.close();
    } catch (_) {}

    _socket =
        null;

    _client =
        null;

    _dc =
        dc;
  }

  // ============================================================
  // DISCONNECT
  // ============================================================

  Future<void>
      _disconnectAuxiliaryClients() async {
    final sockets =
        _dcSockets.values
            .toList();

    _dcClients.clear();

    _dcSockets.clear();

    _dcClientFutures.clear();

    for (final socket
        in sockets) {
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  Future<void>
      _disconnectDownloadClients() async {
    final sockets =
        _downloadSockets.values
            .toList();

    _downloadClients.clear();

    _downloadSockets.clear();

    _downloadClientFutures.clear();

    for (final socket
        in sockets) {
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  Future<void> disconnect() async {
    await _disconnectDownloadClients();

    await _disconnectAuxiliaryClients();

    try {
      await _socket?.close();
    } catch (_) {}

    _socket =
        null;

    _client =
        null;
  }

  Future<void> dispose() async {
    await disconnect();

    await _logsController.close();
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