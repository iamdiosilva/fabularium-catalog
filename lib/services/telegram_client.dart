import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  final StreamController<Object>
      _logsController =
      StreamController<Object>.broadcast();

  Stream<Object> get logs =>
      _logsController.stream;

  tg.Client? get client =>
      _client;

  bool get hasSavedSession =>
      File(_sessionFileName).existsSync();

  void _log(Object value) {
    if (!_logsController.isClosed) {
      _logsController.add(value);
    }
  }

  Future<tg.Client> connect() async {
    final existingClient =
        _client;

    if (existingClient != null) {
      return existingClient;
    }

    /*
     * Primeiro carrega a sessão.
     *
     * Isso também restaura o DC correto.
     */
    final session =
        _loadSession();

    final savedAuthorizationKey =
        session?.authorizationKey;

    if (session != null) {
      _dc = session.dc;

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

    _log(
      'Socket conectado.',
    );

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
        'AuthorizationKey restaurada.',
      );
    } else {
      _log(
        'Criando nova AuthorizationKey...',
      );

      authorizationKey =
          await tg.Client.authorize(
        telegramSocket,
        obfuscation,
        idGenerator,
      );

      _log(
        'AuthorizationKey criada.',
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

    client.stream.listen(
      (event) {
        _log(event);
      },
      onError: (error) {
        _log(
          'Erro no stream Telegram: $error',
        );
      },
    );

    _log(
      'Inicializando Telegram...',
    );

    final configResponse =
        await client
            .initConnection<
                t.Config>(
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
            .whereType<
                t.DcOption>(),
      );
    }

    _client =
        client;

    _log(
      'Telegram conectado no DC ${_dc.id}.',
    );

    return client;
  }

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
      jsonEncode(data),
      flush: true,
    );

    _log(
      'Sessão salva no DC ${_dc.id}.',
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

      final content =
          file
              .readAsStringSync();

      final decoded =
          jsonDecode(
        content,
      );

      if (decoded
          is! Map<String, dynamic>) {
        return null;
      }

      /*
       * Detecta sessão antiga.
       *
       * Nossa versão anterior salvava
       * somente:
       *
       * {
       *   id,
       *   key,
       *   salt
       * }
       *
       * Não sabemos em qual DC essa
       * chave foi criada.
       */
      if (!decoded.containsKey(
        'authorizationKey',
      )) {
        _log(
          'Sessão antiga encontrada. '
          'Ela será ignorada.',
        );

        return null;
      }

      final authData =
          decoded[
              'authorizationKey'];

      final dcData =
          decoded['dc'];

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
        ipv6: false,
        mediaOnly: false,
        tcpoOnly: false,
        cdn: false,
        static: false,
        thisPortOnly: false,
        id:
            dcData['id']
                as int,
        ipAddress:
            dcData[
                    'ipAddress']
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
    } catch (e) {
      _log(
        'Não foi possível carregar '
        'a sessão: $e',
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

  Future<void> changeDataCenter(
    t.DcOption dc,
  ) async {
    _log(
      'Mudando do DC ${_dc.id} '
      'para o DC ${dc.id}.',
    );

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

  t.DcOption? findDataCenter(
    int id,
  ) {
    for (final dc
        in dcs) {
      if (dc.id == id &&
          !dc.ipv6 &&
          !dc.mediaOnly &&
          !dc.cdn) {
        return dc;
      }
    }

    return null;
  }

  Future<void> disconnect() async {
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

    await _logsController
        .close();
  }
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