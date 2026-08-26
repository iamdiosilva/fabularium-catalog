import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:t/t.dart' as t;
import 'package:tg/tg.dart' as tg;

import '../config/telegram_config.dart';
import 'telegram_client.dart';
import 'telegram_socket.dart';

class TelegramStorageUploadConnectionPool {
  final TelegramClient telegramClient;

  final List<tg.Client> _clients =
      <tg.Client>[];

  final List<TelegramSocket> _sockets =
      <TelegramSocket>[];

  bool _isOpening =
      false;

  bool _isClosed =
      false;

  TelegramStorageUploadConnectionPool({
    required this.telegramClient,
  });

  List<tg.Client> get clients =>
      List<tg.Client>.unmodifiable(
        _clients,
      );

  int get size =>
      _clients.length;

  Future<void> open({
    int size = 8,
  }) async {
    if (_isClosed) {
      throw const TelegramStorageUploadConnectionPoolException(
        'The upload connection pool is already closed.',
      );
    }

    if (_clients.isNotEmpty) {
      return;
    }

    if (_isOpening) {
      throw const TelegramStorageUploadConnectionPoolException(
        'The upload connection pool is already opening.',
      );
    }

    if (size <= 0) {
      throw const TelegramStorageUploadConnectionPoolException(
        'Upload connection pool size must be greater than zero.',
      );
    }

    _isOpening =
        true;

    try {
      final mainClient =
          await telegramClient.connect();

      final savedDc =
          await _loadCurrentDataCenter();

      final dc =
          telegramClient.findDataCenter(
                savedDc.id,
              ) ??
              savedDc;

      final operations =
          <Future<void>>[];

      for (int slot = 0;
          slot < size;
          slot++) {
        operations.add(
          _openSlot(
            mainClient:
                mainClient,
            dc:
                dc,
            slot:
                slot,
          ).then(
            (
              connection,
            ) async {
              if (_isClosed) {
                await connection.socket
                    .close();

                return;
              }

              _clients.add(
                connection.client,
              );

              _sockets.add(
                connection.socket,
              );
            },
          ),
        );
      }

      await Future.wait(
        operations,
      );

      if (_clients.length !=
          size) {
        throw TelegramStorageUploadConnectionPoolException(
          'Could not open the complete upload connection pool. '
          'Expected $size connections, got ${_clients.length}.',
        );
      }
    } catch (e) {
      await close();

      if (e is TelegramStorageUploadConnectionPoolException) {
        rethrow;
      }

      throw TelegramStorageUploadConnectionPoolException(
        'Could not open Telegram upload connections: $e',
      );
    } finally {
      _isOpening =
          false;
    }
  }

  Future<_TelegramStorageUploadConnection>
      _openSlot({
    required tg.Client mainClient,
    required t.DcOption dc,
    required int slot,
  }) async {
    final authorizationKey =
        tg.AuthorizationKey.fromJson(
      mainClient.authorizationKey
          .toJson(),
    );

    final rawSocket =
        await Socket.connect(
      dc.ipAddress,
      dc.port,
      timeout:
          const Duration(
        seconds:
            15,
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

      /*
       * Cada conexão possui o próprio Client,
       * MessageIdGenerator, sessão e socket.
       *
       * A AuthorizationKey pode ser clonada,
       * assim como o Fabularium já faz com
       * as conexões paralelas de download.
       */
      client.stream.listen(
        (_) {},
        onError:
            (_) {},
      );

      final response =
          await client
              .initConnection<t.Config>(
        apiId:
            TelegramConfig.apiId,
        deviceModel:
            'Fabularium Catalog Upload V3 $slot',
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
      )
              .timeout(
        const Duration(
          seconds:
              30,
        ),
      );

      if (response.error !=
          null) {
        throw Exception(
          response
              .error!
              .errorMessage,
        );
      }

      return _TelegramStorageUploadConnection(
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

  Future<t.DcOption>
      _loadCurrentDataCenter() async {
    final primary =
        File(
      _sessionFilePath(),
    );

    final legacy =
        File(
      p.join(
        Directory.current.path,
        'telegram_auth.json',
      ),
    );

    File? file;

    if (await primary.exists()) {
      file =
          primary;
    } else if (await legacy.exists()) {
      file =
          legacy;
    }

    if (file ==
        null) {
      throw const TelegramStorageUploadConnectionPoolException(
        'Telegram session file was not found. '
        'The upload pool cannot determine the current data center.',
      );
    }

    dynamic decoded;

    try {
      decoded =
          jsonDecode(
        await file.readAsString(),
      );
    } catch (e) {
      throw TelegramStorageUploadConnectionPoolException(
        'Could not read Telegram session data center: $e',
      );
    }

    if (decoded is! Map) {
      throw const TelegramStorageUploadConnectionPoolException(
        'Invalid Telegram session file.',
      );
    }

    final root =
        Map<String, dynamic>.from(
      decoded,
    );

    final rawDc =
        root['dc'];

    if (rawDc is! Map) {
      throw const TelegramStorageUploadConnectionPoolException(
        'Telegram session does not contain data center information.',
      );
    }

    final dc =
        Map<String, dynamic>.from(
      rawDc,
    );

    final id =
        _readInt(
      dc['id'],
    );

    final port =
        _readInt(
      dc['port'],
    );

    final ipAddress =
        dc['ipAddress']
            ?.toString()
            .trim();

    if (id ==
            null ||
        port ==
            null ||
        ipAddress ==
            null ||
        ipAddress.isEmpty) {
      throw const TelegramStorageUploadConnectionPoolException(
        'Telegram session contains invalid data center information.',
      );
    }

    return t.DcOption(
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
          id,
      ipAddress:
          ipAddress,
      port:
          port,
    );
  }

  String _sessionFilePath() {
    final localAppData =
        Platform.environment[
            'LOCALAPPDATA'];

    final basePath =
        localAppData !=
                    null &&
                localAppData.isNotEmpty
            ? localAppData
            : Directory.systemTemp.path;

    return p.join(
      basePath,
      'Fabularium',
      'Telegram',
      'telegram_auth.json',
    );
  }

  int? _readInt(
    dynamic value,
  ) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value?.toString() ??
          '',
    );
  }

  tg.Client clientForPart(
    int partIndex,
  ) {
    if (_clients.isEmpty) {
      throw const TelegramStorageUploadConnectionPoolException(
        'Upload connection pool is not open.',
      );
    }

    return _clients[
        partIndex %
            _clients.length];
  }

  Future<void> close() async {
    if (_isClosed) {
      return;
    }

    _isClosed =
        true;

    final sockets =
        List<TelegramSocket>.from(
      _sockets,
    );

    _clients.clear();
    _sockets.clear();

    await Future.wait(
      sockets.map(
        (
          socket,
        ) async {
          try {
            await socket.close();
          } catch (_) {}
        },
      ),
    );
  }
}

class _TelegramStorageUploadConnection {
  final tg.Client client;

  final TelegramSocket socket;

  const _TelegramStorageUploadConnection({
    required this.client,
    required this.socket,
  });
}

class TelegramStorageUploadConnectionPoolException
    implements Exception {
  final String message;

  const TelegramStorageUploadConnectionPoolException(
    this.message,
  );

  @override
  String toString() =>
      message;
}
