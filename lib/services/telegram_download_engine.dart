import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:t/t.dart' as t;

import '../models/telegram_media.dart';
import 'telegram_client.dart';

class TelegramDownloadEngine {
  TelegramDownloadEngine._();

  static final TelegramDownloadEngine instance =
      TelegramDownloadEngine._();

  final TelegramClient _telegramClient =
      TelegramClient.instance;

  /*
   * Limite máximo usado pelo upload.getFile.
   */
  static const int _chunkSize =
      1024 * 1024;

  /*
   * Quatro conexões MTProto dedicadas.
   */
  static const int _connectionCount =
      4;

  /*
   * Oito requests simultâneos.
   *
   * Cada conexão normalmente terá
   * dois requests em voo.
   */
  static const int _maxInFlight =
      8;

  Future<String> downloadMedia(
    TelegramMedia media, {
    required String groupTitle,
    void Function(
      int received,
      int total,
    )?
        onProgress,
  }) async {
    final directory =
        await _getDownloadDirectory(
      groupTitle,
    );

    final destination =
        File(
      p.join(
        directory.path,
        _sanitizeFileName(
          media.fileName,
        ),
      ),
    );

    return _downloadLocation(
      initialDcId:
          media.dcId,
      location:
          media.location,
      destination:
          destination,
      expectedSize:
          media.size,
      onProgress:
          onProgress,
    );
  }

  Future<String> _downloadLocation({
    required int initialDcId,
    required t.InputFileLocationBase
        location,
    required File destination,
    required int expectedSize,
    void Function(
      int received,
      int total,
    )?
        onProgress,
  }) async {
    await destination.parent.create(
      recursive:
          true,
    );

    if (await destination.exists()) {
      final size =
          await destination.length();

      if (expectedSize <= 0 ||
          size ==
              expectedSize) {
        onProgress?.call(
          size,
          expectedSize,
        );

        return destination.path;
      }
    }

    final tempFile =
        File(
      '${destination.path}.part',
    );

    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    /*
     * Antes de começar o arquivo, abrimos
     * o pool inteiro.
     *
     * Isso evita perder desempenho criando
     * conexão no meio do download.
     */
    await _telegramClient
        .warmDownloadPool(
      initialDcId,
      size:
          _connectionCount,
    );

    final randomAccessFile =
        await tempFile.open(
      mode:
          FileMode.write,
    );

    /*
     * Pré-aloca o espaço do arquivo.
     *
     * Isso reduz fragmentação no disco e
     * permite escrita fora de ordem.
     */
    if (expectedSize >
        0) {
      await randomAccessFile
          .truncate(
        expectedSize,
      );
    }

    final writer =
        _RandomAccessWriter(
      randomAccessFile,
    );

    final inFlight =
        <int,
            Future<_TelegramDownloadChunk>>{};

    int nextOffset =
        0;

    int nextChunkIndex =
        0;

    int receivedBytes =
        0;

    int? discoveredEnd;

    void fillWindow() {
      while (inFlight.length <
          _maxInFlight) {
        if (expectedSize >
                0 &&
            nextOffset >=
                expectedSize) {
          break;
        }

        if (discoveredEnd !=
                null &&
            nextOffset >=
                discoveredEnd!) {
          break;
        }

        final offset =
            nextOffset;

        final slot =
            nextChunkIndex %
                _connectionCount;

        inFlight[
                offset] =
            _downloadChunk(
          initialDcId:
              initialDcId,
          slot:
              slot,
          location:
              location,
          offset:
              offset,
        );

        nextOffset +=
            _chunkSize;

        nextChunkIndex++;
      }
    }

    try {
      /*
       * Primeiro enchemos a janela.
       *
       * 8 MB ficam sendo requisitados
       * simultaneamente.
       */
      fillWindow();

      while (inFlight.isNotEmpty) {
        /*
         * Aguarda QUALQUER request terminar.
         *
         * Não esperamos mais o lote inteiro.
         */
        final chunk =
            await Future.any(
          inFlight.values,
        );

        inFlight.remove(
          chunk.offset,
        );

        /*
         * Arquivo sem tamanho conhecido:
         *
         * chunk menor que 1 MB indica
         * que encontramos o final.
         */
        if (chunk.bytes.length <
            _chunkSize) {
          final end =
              chunk.offset +
                  chunk.bytes.length;

          if (discoveredEnd ==
                  null ||
              end <
                  discoveredEnd!) {
            discoveredEnd =
                end;
          }
        }

        /*
         * Requests que já estavam em voo
         * podem ter ultrapassado o final
         * descoberto.
         */
        if (discoveredEnd !=
                null &&
            chunk.offset >=
                discoveredEnd!) {
          fillWindow();

          continue;
        }

        if (chunk.bytes.isNotEmpty) {
          /*
           * Escrevemos na posição original
           * do chunk.
           *
           * As respostas podem chegar:
           *
           * 3
           * 1
           * 4
           * 2
           *
           * e ainda assim o arquivo final
           * permanece correto.
           */
          await writer.writeAt(
            chunk.offset,
            chunk.bytes,
          );

          receivedBytes +=
              chunk.bytes.length;

          onProgress?.call(
            receivedBytes,
            expectedSize,
          );
        }

        /*
         * Assim que UM request termina,
         * imediatamente colocamos outro.
         *
         * Isso mantém a janela cheia.
         */
        fillWindow();
      }

      await writer.flush();

      /*
       * Não usamos File.length aqui porque
       * pré-alocamos o arquivo.
       *
       * Validamos pelos bytes realmente
       * recebidos.
       */
      if (expectedSize >
              0 &&
          receivedBytes <
              expectedSize) {
        throw Exception(
          'Download incompleto. '
          'Esperado: $expectedSize bytes. '
          'Recebido: $receivedBytes bytes.',
        );
      }
    } catch (_) {
      try {
        await writer.close();
      } catch (_) {}

      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}

      rethrow;
    }

    await writer.close();

    if (await destination.exists()) {
      await destination.delete();
    }

    final completed =
        await tempFile.rename(
      destination.path,
    );

    final finalSize =
        expectedSize >
                0
            ? expectedSize
            : await completed.length();

    onProgress?.call(
      finalSize,
      finalSize,
    );

    return completed.path;
  }

  Future<_TelegramDownloadChunk>
      _downloadChunk({
    required int initialDcId,
    required int slot,
    required t.InputFileLocationBase
        location,
    required int offset,
  }) async {
    int dcId =
        initialDcId;

    int migrationCount =
        0;

    const maxMigrations =
        3;

    while (true) {
      final client =
          await _telegramClient
              .getDownloadClientForDataCenter(
        dcId,
        slot,
      );

      final response =
          await client.upload
              .getFile(
        precise:
            false,
        cdnSupported:
            false,
        location:
            location,
        offset:
            offset,
        limit:
            _chunkSize,
      );

      final error =
          response.error;

      if (error != null) {
        final migrateDc =
            _extractMigrationDc(
          error.errorMessage,
        );

        if (migrateDc != null) {
          migrationCount++;

          if (migrationCount >
              maxMigrations) {
            throw Exception(
              'Muitas migrações de '
              'Data Center durante download.',
            );
          }

          dcId =
              migrateDc;

          continue;
        }

        throw Exception(
          error.errorMessage,
        );
      }

      final dynamic result =
          response.result;

      if (result == null) {
        throw Exception(
          'Telegram retornou resposta '
          'de arquivo vazia.',
        );
      }

      Uint8List bytes;

      try {
        final dynamic rawBytes =
            result.bytes;

        if (rawBytes is Uint8List) {
          bytes =
              rawBytes;
        } else {
          bytes =
              Uint8List.fromList(
            List<int>.from(
              rawBytes as List,
            ),
          );
        }
      } catch (_) {
        throw Exception(
          'Formato de arquivo retornado '
          'pelo Telegram não suportado.',
        );
      }

      return _TelegramDownloadChunk(
        offset:
            offset,
        bytes:
            bytes,
        dcId:
            dcId,
      );
    }
  }

  int? _extractMigrationDc(
    String message,
  ) {
    const prefixes =
        <String>[
      'FILE_MIGRATE_',
      'NETWORK_MIGRATE_',
    ];

    for (final prefix
        in prefixes) {
      if (!message.startsWith(
        prefix,
      )) {
        continue;
      }

      return int.tryParse(
        message
            .substring(
          prefix.length,
        )
            .trim(),
      );
    }

    return null;
  }

  Future<Directory>
      _getDownloadDirectory(
    String groupTitle,
  ) async {
    final userProfile =
        Platform.environment[
            'USERPROFILE'];

    final basePath =
        userProfile != null &&
                userProfile.isNotEmpty
            ? p.join(
                userProfile,
                'Downloads',
              )
            : Directory.current.path;

    final directory =
        Directory(
      p.join(
        basePath,
        'Fabularium',
        'Telegram',
        _sanitizeFileName(
          groupTitle,
        ),
      ),
    );

    await directory.create(
      recursive:
          true,
    );

    return directory;
  }

  String _sanitizeFileName(
    String value,
  ) {
    var result =
        value.replaceAll(
      RegExp(
        r'[<>:"/\\|?*\x00-\x1F]',
      ),
      '_',
    );

    result =
        result.trim();

    while (result.endsWith(
          '.',
        ) ||
        result.endsWith(
          ' ',
        )) {
      result =
          result.substring(
        0,
        result.length - 1,
      );
    }

    return result.isEmpty
        ? 'telegram_file'
        : result;
  }
}

class _TelegramDownloadChunk {
  final int offset;

  final Uint8List bytes;

  final int dcId;

  const _TelegramDownloadChunk({
    required this.offset,
    required this.bytes,
    required this.dcId,
  });
}

class _RandomAccessWriter {
  final RandomAccessFile _file;

  Future<void> _tail =
      Future<void>.value();

  _RandomAccessWriter(
    this._file,
  );

  Future<void> writeAt(
    int offset,
    Uint8List bytes,
  ) {
    final operation =
        _tail.then(
      (_) async {
        await _file.setPosition(
          offset,
        );

        await _file.writeFrom(
          bytes,
        );
      },
    );

    _tail =
        operation;

    return operation;
  }

  Future<void> flush() async {
    await _tail;

    await _file.flush();
  }

  Future<void> close() async {
    try {
      await _tail;
    } finally {
      await _file.close();
    }
  }
}