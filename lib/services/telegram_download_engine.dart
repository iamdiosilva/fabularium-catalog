import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:t/t.dart' as t;

import '../models/telegram_media.dart';
import 'telegram_client.dart';
import 'telegram_file_service.dart';

class TelegramDownloadEngine {
  TelegramDownloadEngine._();

  static final TelegramDownloadEngine instance =
      TelegramDownloadEngine._();

  final TelegramClient _telegramClient =
      TelegramClient.instance;

  final TelegramFileService _files =
      TelegramFileService.instance;

  static const int _chunkSize =
      1024 * 1024;

  static const int _previewChunkSize =
      512 * 1024;

  static const int _connectionCount =
      4;

  static const int _defaultMaxInFlight =
      4;

  /*
   * Não gravamos metadata a cada chunk.
   *
   * Fazemos checkpoint a cada 32 MB ou 2 segundos.
   *
   * Em uma interrupção abrupta, no pior caso
   * alguns MB já baixados serão baixados novamente,
   * mas nunca pularemos uma região incompleta.
   */
  static const int _resumeCheckpointBytes =
      32 * 1024 * 1024;

  static const Duration _resumeCheckpointInterval =
      Duration(
    seconds: 2,
  );

  static const int _resumeMetadataVersion =
      1;

  // ============================================================
  // LARGE FILE DOWNLOAD
  // ============================================================

  Future<String> downloadMedia(
    TelegramMedia media, {
    required String groupTitle,
    void Function(
      int received,
      int total,
    )?
        onProgress,
    int Function()? maxInFlightProvider,
    Duration Function()? yieldDelayProvider,
  }) async {
    final destination =
        _files.downloadFile(
      media,
      groupTitle:
          groupTitle,
    );

    return _downloadLargeLocation(
      initialDcId:
          media.dcId,
      location:
          media.location,
      destination:
          destination,
      expectedSize:
          media.size,
      resumeKey:
          media.cacheKey,
      onProgress:
          onProgress,
      maxInFlightProvider:
          maxInFlightProvider,
      yieldDelayProvider:
          yieldDelayProvider,
    );
  }

  // ============================================================
  // PREVIEW DOWNLOAD
  // ============================================================

  Future<String> downloadPreview(
    TelegramMedia media,
  ) async {
    final location =
        media.previewLocation;

    if (location == null) {
      throw StateError(
        'Preview is not available.',
      );
    }

    final destination =
        _files.previewFile(
      media,
    );

    return _downloadSmallLocation(
      initialDcId:
          media.dcId,
      location:
          location,
      destination:
          destination,
      expectedSize:
          media.previewSize ?? 0,
    );
  }

  // ============================================================
  // HIGH PERFORMANCE FILE
  // ============================================================

  Future<String> _downloadLargeLocation({
    required int initialDcId,
    required t.InputFileLocationBase location,
    required File destination,
    required int expectedSize,
    required String resumeKey,
    void Function(
      int received,
      int total,
    )?
        onProgress,
    int Function()? maxInFlightProvider,
    Duration Function()? yieldDelayProvider,
  }) async {
    await destination.parent.create(
      recursive: true,
    );

    final tempFile =
        File(
      '${destination.path}.part',
    );

    final metadataFile =
        File(
      '${destination.path}.part.resume.json',
    );

    // ==========================================================
    // ALREADY COMPLETED
    // ==========================================================

    if (await destination.exists()) {
      final size =
          await destination.length();

      if (expectedSize <= 0 ||
          size == expectedSize) {
        /*
         * Se o arquivo final já está correto,
         * podemos remover qualquer sobra antiga
         * de .part / metadata.
         */
        await _deleteFileBestEffort(
          tempFile,
        );

        await _deleteResumeMetadata(
          metadataFile,
        );

        onProgress?.call(
          size,
          expectedSize > 0
              ? expectedSize
              : size,
        );

        return destination.path;
      }
    }

    // ==========================================================
    // PREPARE RESUME
    // ==========================================================

    final resumeState =
        await _prepareResumeState(
      tempFile:
          tempFile,
      metadataFile:
          metadataFile,
      expectedSize:
          expectedSize,
      resumeKey:
          resumeKey,
    );

    int committedBytes =
        resumeState.committedBytes;

    /*
     * O progress inicial já começa de onde
     * conseguimos retomar.
     */
    if (committedBytes > 0) {
      onProgress?.call(
        committedBytes,
        expectedSize,
      );
    }

    /*
     * Pode acontecer de o download ter terminado
     * e a aplicação ter sido encerrada antes do
     * rename .part -> arquivo final.
     *
     * Nesse caso não precisamos nem conectar
     * ao Telegram novamente.
     */
    if (expectedSize > 0 &&
        committedBytes == expectedSize &&
        await tempFile.exists() &&
        await tempFile.length() == expectedSize) {
      if (await destination.exists()) {
        await destination.delete();
      }

      final completed =
          await tempFile.rename(
        destination.path,
      );

      await _deleteResumeMetadata(
        metadataFile,
      );

      onProgress?.call(
        expectedSize,
        expectedSize,
      );

      return completed.path;
    }

    // ==========================================================
    // CONNECTION POOL
    // ==========================================================

    await _telegramClient.warmDownloadPool(
      initialDcId,
      size:
          _connectionCount,
    );

    // ==========================================================
    // OPEN PART FILE
    // ==========================================================

    final bool resuming =
        resumeState.canResume;

    final randomAccessFile =
        await tempFile.open(
      /*
       * FileMode.write truncaria o arquivo.
       *
       * Quando estamos retomando precisamos
       * preservar o conteúdo já confirmado.
       */
      mode:
          resuming
              ? FileMode.append
              : FileMode.write,
    );

    if (!resuming &&
        expectedSize > 0) {
      /*
       * Mantemos a pré-alocação utilizada pelo
       * downloader original.
       *
       * IMPORTANTE:
       * o tamanho desse arquivo NÃO será usado
       * para decidir o offset de resume.
       */
      await randomAccessFile.truncate(
        expectedSize,
      );

      await randomAccessFile.flush();

      /*
       * Criamos metadata inicial somente para
       * arquivos cujo tamanho é conhecido.
       */
      await _writeResumeMetadata(
        metadataFile,
        _ResumeMetadata(
          version:
              _resumeMetadataVersion,
          resumeKey:
              resumeKey,
          expectedSize:
              expectedSize,
          chunkSize:
              _chunkSize,
          committedBytes:
              0,
        ),
      );
    }

    final writer =
        _RandomAccessWriter(
      randomAccessFile,
    );

    // ==========================================================
    // DOWNLOAD STATE
    // ==========================================================

    final inFlight =
        <int, Future<_TelegramDownloadChunk>>{};

    /*
     * Chunks podem terminar fora de ordem.
     *
     * Exemplo:
     *
     * 0 MB    concluído
     * 1 MB    pendente
     * 2 MB    concluído
     * 3 MB    concluído
     *
     * Não podemos salvar committedBytes = 4 MB.
     *
     * O prefixo seguro continua sendo somente 1 MB.
     */
    final completedChunkLengths =
        <int, int>{};

    int nextOffset =
        committedBytes;

    int nextChunkIndex =
        committedBytes ~/ _chunkSize;

    int receivedBytes =
        committedBytes;

    int persistedCommittedBytes =
        committedBytes;

    DateTime lastCheckpoint =
        DateTime.now();

    int? discoveredEnd;

    // ==========================================================
    // MAX IN FLIGHT
    // ==========================================================

    int desiredMaxInFlight() {
      int result =
          maxInFlightProvider?.call() ??
              _defaultMaxInFlight;

      if (result < 1) {
        result =
            1;
      }

      if (result > _connectionCount) {
        result =
            _connectionCount;
      }

      return result;
    }

    // ==========================================================
    // FILL WINDOW
    // ==========================================================

    void fillWindow() {
      final maxInFlight =
          desiredMaxInFlight();

      while (inFlight.length <
          maxInFlight) {
        if (expectedSize > 0 &&
            nextOffset >= expectedSize) {
          break;
        }

        if (discoveredEnd != null &&
            nextOffset >=
                discoveredEnd) {
          break;
        }

        final offset =
            nextOffset;

        final slot =
            nextChunkIndex %
                _connectionCount;

        inFlight[offset] =
            _downloadChunk(
          initialDcId:
              initialDcId,
          slot:
              slot,
          location:
              location,
          offset:
              offset,
          limit:
              _chunkSize,
        );

        nextOffset +=
            _chunkSize;

        nextChunkIndex++;
      }
    }

    // ==========================================================
    // ADVANCE CONTIGUOUS PREFIX
    // ==========================================================

    void advanceCommittedBytes() {
      while (true) {
        final length =
            completedChunkLengths.remove(
          committedBytes,
        );

        if (length == null ||
            length <= 0) {
          break;
        }

        committedBytes +=
            length;

        /*
         * Um chunk menor que _chunkSize representa
         * o final conhecido do arquivo.
         */
        if (length < _chunkSize) {
          break;
        }
      }
    }

    // ==========================================================
    // CHECKPOINT
    // ==========================================================

    Future<void> persistCheckpoint({
      bool force = false,
    }) async {
      if (expectedSize <= 0) {
        return;
      }

      /*
       * Nada novo foi confirmado de forma contínua.
       */
      if (committedBytes <=
          persistedCommittedBytes) {
        return;
      }

      final now =
          DateTime.now();

      final bytesSinceCheckpoint =
          committedBytes -
              persistedCommittedBytes;

      final timeSinceCheckpoint =
          now.difference(
        lastCheckpoint,
      );

      if (!force &&
          bytesSinceCheckpoint <
              _resumeCheckpointBytes &&
          timeSinceCheckpoint <
              _resumeCheckpointInterval) {
        return;
      }

      /*
       * Primeiro garantimos os bytes do arquivo
       * no disco.
       *
       * Somente DEPOIS atualizamos a metadata.
       *
       * Assim a metadata nunca deve prometer
       * um prefixo que ainda não foi persistido.
       */
      await writer.flush();

      await _writeResumeMetadata(
        metadataFile,
        _ResumeMetadata(
          version:
              _resumeMetadataVersion,
          resumeKey:
              resumeKey,
          expectedSize:
              expectedSize,
          chunkSize:
              _chunkSize,
          committedBytes:
              committedBytes,
        ),
      );

      persistedCommittedBytes =
          committedBytes;

      lastCheckpoint =
          now;
    }

    // ==========================================================
    // DOWNLOAD LOOP
    // ==========================================================

    try {
      fillWindow();

      while (inFlight.isNotEmpty) {
        final chunk =
            await Future.any(
          inFlight.values,
        );

        inFlight.remove(
          chunk.offset,
        );

        // -------------------------------------------------------
        // END DISCOVERY
        // -------------------------------------------------------

        if (chunk.bytes.length <
            _chunkSize) {
          final end =
              chunk.offset +
                  chunk.bytes.length;

          if (discoveredEnd == null ||
              end <
                  discoveredEnd) {
            discoveredEnd =
                end;
          }
        }

        /*
         * Se outro request já descobriu o fim
         * antes deste offset, este chunk é uma
         * requisição especulativa e é ignorado.
         */
        if (discoveredEnd != null &&
            chunk.offset >=
                discoveredEnd) {
          fillWindow();

          continue;
        }

        // -------------------------------------------------------
        // WRITE
        // -------------------------------------------------------

        if (chunk.bytes.isNotEmpty) {
          await writer.writeAt(
            chunk.offset,
            chunk.bytes,
          );

          receivedBytes +=
              chunk.bytes.length;

          completedChunkLengths[
                  chunk.offset] =
              chunk.bytes.length;

          advanceCommittedBytes();

          /*
           * receivedBytes representa o progresso
           * visual da operação.
           *
           * committedBytes é o progresso seguro
           * utilizado pelo resume.
           */
          final progress =
              expectedSize > 0 &&
                      receivedBytes >
                          expectedSize
                  ? expectedSize
                  : receivedBytes;

          onProgress?.call(
            progress,
            expectedSize,
          );

          await persistCheckpoint();
        }

        // -------------------------------------------------------
        // PERFORMANCE YIELD
        // -------------------------------------------------------

        final yieldDelay =
            yieldDelayProvider?.call() ??
                Duration.zero;

        if (yieldDelay.inMicroseconds >
            0) {
          await Future<void>.delayed(
            yieldDelay,
          );
        }

        fillWindow();
      }

      // ========================================================
      // FINAL VALIDATION
      // ========================================================

      if (expectedSize > 0) {
        /*
         * Essa validação é diferente de simplesmente
         * verificar tempFile.length().
         *
         * O .part é pré-alocado desde o início.
         *
         * Só committedBytes garante que todos os
         * bytes de 0 até expectedSize chegaram.
         */
        if (committedBytes <
            expectedSize) {
          /*
           * Salvamos tudo que conseguimos confirmar
           * antes de reportar o erro.
           */
          await persistCheckpoint(
            force: true,
          );

          throw Exception(
            'Incomplete download. '
            'Expected: $expectedSize bytes. '
            'Committed: $committedBytes bytes.',
          );
        }

        await persistCheckpoint(
          force: true,
        );
      } else {
        /*
         * Para arquivos sem tamanho conhecido
         * ainda não habilitamos resume.
         *
         * Entretanto removemos qualquer região
         * especulativa escrita depois do EOF.
         */
        if (discoveredEnd != null) {
          await writer.truncate(
            discoveredEnd,
          );
        }

        await writer.flush();
      }
    } catch (_) {
      /*
       * DIFERENÇA FUNDAMENTAL PARA A VERSÃO ANTIGA:
       *
       * NÃO apagamos mais o .part.
       *
       * Tentamos salvar o último prefixo contínuo
       * confirmado e deixamos o arquivo disponível
       * para a próxima tentativa.
       */
      try {
        await persistCheckpoint(
          force: true,
        );
      } catch (_) {}

      try {
        await writer.close();
      } catch (_) {}

      rethrow;
    }

    // ==========================================================
    // CLOSE PART FILE
    // ==========================================================

    await writer.close();

    // ==========================================================
    // PHYSICAL SIZE VALIDATION
    // ==========================================================

    if (expectedSize > 0) {
      final partSize =
          await tempFile.length();

      if (partSize !=
          expectedSize) {
        /*
         * Não apagamos.
         *
         * Na próxima tentativa _prepareResumeState
         * perceberá que o arquivo físico não é
         * compatível e começará novamente.
         */
        throw Exception(
          'Invalid partial file size. '
          'Expected: $expectedSize bytes. '
          'Found: $partSize bytes.',
        );
      }
    }

    // ==========================================================
    // FINALIZE
    // ==========================================================

    if (await destination.exists()) {
      await destination.delete();
    }

    final completed =
        await tempFile.rename(
      destination.path,
    );

    /*
     * O arquivo final já existe.
     * Metadata de resume não é mais necessária.
     */
    await _deleteResumeMetadata(
      metadataFile,
    );

    final finalSize =
        expectedSize > 0
            ? expectedSize
            : await completed.length();

    onProgress?.call(
      finalSize,
      finalSize,
    );

    return completed.path;
  }

  // ============================================================
  // RESUME STATE
  // ============================================================

  Future<_ResumeState> _prepareResumeState({
    required File tempFile,
    required File metadataFile,
    required int expectedSize,
    required String resumeKey,
  }) async {
    /*
     * Resume só é seguro quando sabemos o
     * tamanho final do arquivo.
     *
     * Na prática documentos Telegram normalmente
     * possuem esse valor.
     */
    if (expectedSize <= 0) {
      await _deleteFileBestEffort(
        tempFile,
      );

      await _deleteResumeMetadata(
        metadataFile,
      );

      return const _ResumeState(
        canResume:
            false,
        committedBytes:
            0,
      );
    }

    final metadata =
        await _loadBestResumeMetadata(
      metadataFile:
          metadataFile,
      expectedSize:
          expectedSize,
      resumeKey:
          resumeKey,
    );

    if (metadata == null ||
        !await tempFile.exists()) {
      await _deleteFileBestEffort(
        tempFile,
      );

      await _deleteResumeMetadata(
        metadataFile,
      );

      return const _ResumeState(
        canResume:
            false,
        committedBytes:
            0,
      );
    }

    int partSize;

    try {
      partSize =
          await tempFile.length();
    } catch (_) {
      await _deleteFileBestEffort(
        tempFile,
      );

      await _deleteResumeMetadata(
        metadataFile,
      );

      return const _ResumeState(
        canResume:
            false,
        committedBytes:
            0,
      );
    }

    /*
     * O arquivo .part é pré-alocado para
     * expectedSize.
     *
     * Se o tamanho mudou, não confiamos nele.
     */
    if (partSize !=
        expectedSize) {
      await _deleteFileBestEffort(
        tempFile,
      );

      await _deleteResumeMetadata(
        metadataFile,
      );

      return const _ResumeState(
        canResume:
            false,
        committedBytes:
            0,
      );
    }

    return _ResumeState(
      canResume:
          true,
      committedBytes:
          metadata.committedBytes,
    );
  }

  // ============================================================
  // RESUME METADATA LOAD
  // ============================================================

  Future<_ResumeMetadata?>
      _loadBestResumeMetadata({
    required File metadataFile,
    required int expectedSize,
    required String resumeKey,
  }) async {
    /*
     * Durante a gravação atômica podemos ter:
     *
     * arquivo.resume.json
     * arquivo.resume.json.tmp
     *
     * Se a aplicação fechou no meio do rename,
     * escolhemos o checkpoint válido com maior
     * committedBytes.
     */
    final candidates =
        <File>[
      metadataFile,
      File(
        '${metadataFile.path}.tmp',
      ),
    ];

    _ResumeMetadata? best;

    for (final file
        in candidates) {
      final metadata =
          await _readResumeMetadata(
        file,
      );

      if (metadata == null) {
        continue;
      }

      if (!_isCompatibleResumeMetadata(
        metadata,
        expectedSize:
            expectedSize,
        resumeKey:
            resumeKey,
      )) {
        continue;
      }

      if (best == null ||
          metadata.committedBytes >
              best.committedBytes) {
        best =
            metadata;
      }
    }

    return best;
  }

  Future<_ResumeMetadata?>
      _readResumeMetadata(
    File file,
  ) async {
    try {
      if (!await file.exists()) {
        return null;
      }

      final raw =
          await file.readAsString();

      final decoded =
          jsonDecode(
        raw,
      );

      if (decoded is! Map) {
        return null;
      }

      final map =
          Map<String, dynamic>.from(
        decoded,
      );

      final version =
          map['version'];

      final resumeKey =
          map['resumeKey'];

      final expectedSize =
          map['expectedSize'];

      final chunkSize =
          map['chunkSize'];

      final committedBytes =
          map['committedBytes'];

      if (version is! int ||
          resumeKey is! String ||
          expectedSize is! int ||
          chunkSize is! int ||
          committedBytes is! int) {
        return null;
      }

      return _ResumeMetadata(
        version:
            version,
        resumeKey:
            resumeKey,
        expectedSize:
            expectedSize,
        chunkSize:
            chunkSize,
        committedBytes:
            committedBytes,
      );
    } catch (_) {
      return null;
    }
  }

  bool _isCompatibleResumeMetadata(
    _ResumeMetadata metadata, {
    required int expectedSize,
    required String resumeKey,
  }) {
    if (metadata.version !=
        _resumeMetadataVersion) {
      return false;
    }

    if (metadata.resumeKey !=
        resumeKey) {
      return false;
    }

    if (metadata.expectedSize !=
        expectedSize) {
      return false;
    }

    if (metadata.chunkSize !=
        _chunkSize) {
      return false;
    }

    if (metadata.committedBytes <
            0 ||
        metadata.committedBytes >
            expectedSize) {
      return false;
    }

    /*
     * Todo checkpoint intermediário termina
     * exatamente na fronteira de um chunk.
     *
     * A única exceção é o tamanho final.
     */
    if (metadata.committedBytes !=
            expectedSize &&
        metadata.committedBytes %
                _chunkSize !=
            0) {
      return false;
    }

    return true;
  }

  // ============================================================
  // RESUME METADATA WRITE
  // ============================================================

  Future<void> _writeResumeMetadata(
    File metadataFile,
    _ResumeMetadata metadata,
  ) async {
    await metadataFile.parent.create(
      recursive: true,
    );

    final tempMetadata =
        File(
      '${metadataFile.path}.tmp',
    );

    final data =
        <String, dynamic>{
      'version':
          metadata.version,
      'resumeKey':
          metadata.resumeKey,
      'expectedSize':
          metadata.expectedSize,
      'chunkSize':
          metadata.chunkSize,
      'committedBytes':
          metadata.committedBytes,
    };

    /*
     * Primeiro gravamos o novo checkpoint
     * em .tmp e fazemos flush.
     */
    await tempMetadata.writeAsString(
      jsonEncode(
        data,
      ),
      flush: true,
    );

    /*
     * Depois substituímos o metadata principal.
     *
     * Se o processo fechar entre delete/rename,
     * _loadBestResumeMetadata também sabe ler
     * o .tmp.
     */
    if (await metadataFile.exists()) {
      await metadataFile.delete();
    }

    await tempMetadata.rename(
      metadataFile.path,
    );
  }

  Future<void> _deleteResumeMetadata(
    File metadataFile,
  ) async {
    await _deleteFileBestEffort(
      metadataFile,
    );

    await _deleteFileBestEffort(
      File(
        '${metadataFile.path}.tmp',
      ),
    );
  }

  Future<void> _deleteFileBestEffort(
    File file,
  ) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  // ============================================================
  // SMALL FILE / PREVIEW
  // ============================================================

  Future<String> _downloadSmallLocation({
    required int initialDcId,
    required t.InputFileLocationBase location,
    required File destination,
    required int expectedSize,
  }) async {
    await destination.parent.create(
      recursive: true,
    );

    if (await destination.exists()) {
      if (expectedSize <= 0) {
        return destination.path;
      }

      final existingSize =
          await destination.length();

      if (existingSize ==
          expectedSize) {
        return destination.path;
      }
    }

    final temp =
        File(
      '${destination.path}.part',
    );

    /*
     * Preview continua sem resume.
     *
     * São arquivos pequenos e já possuem seu
     * próprio worker/fila.
     */
    if (await temp.exists()) {
      await temp.delete();
    }

    int dcId =
        initialDcId;

    var client =
        await _telegramClient
            .getDownloadClientForDataCenter(
      dcId,
      0,
    );

    int offset =
        0;

    int migrations =
        0;

    final output =
        await temp.open(
      mode: FileMode.write,
    );

    try {
      while (true) {
        final response =
            await client.upload.getFile(
          precise:
              false,
          cdnSupported:
              false,
          location:
              location,
          offset:
              offset,
          limit:
              _previewChunkSize,
        );

        if (response.error != null) {
          final errorMessage =
              response
                  .error!
                  .errorMessage;

          final migrateDc =
              _extractMigrationDc(
            errorMessage,
          );

          if (migrateDc != null) {
            migrations++;

            if (migrations > 3) {
              throw Exception(
                'Too many Telegram DC migrations.',
              );
            }

            dcId =
                migrateDc;

            client =
                await _telegramClient
                    .getDownloadClientForDataCenter(
              dcId,
              0,
            );

            continue;
          }

          throw Exception(
            errorMessage,
          );
        }

        final dynamic result =
            response.result;

        if (result == null) {
          throw Exception(
            'Telegram returned an empty preview response.',
          );
        }

        final bytes =
            _readBytes(
          result,
        );

        if (bytes.isEmpty) {
          break;
        }

        await output.writeFrom(
          bytes,
        );

        offset +=
            bytes.length;

        if (expectedSize > 0 &&
            offset >= expectedSize) {
          break;
        }

        if (bytes.length <
            _previewChunkSize) {
          break;
        }
      }
    } finally {
      await output.close();
    }

    if (expectedSize > 0) {
      final downloaded =
          await temp.length();

      if (downloaded <
          expectedSize) {
        try {
          await temp.delete();
        } catch (_) {}

        throw Exception(
          'Incomplete Telegram preview.',
        );
      }
    }

    if (await destination.exists()) {
      await destination.delete();
    }

    return temp.rename(
      destination.path,
    ).then(
      (
        file,
      ) =>
          file.path,
    );
  }

  // ============================================================
  // CHUNK
  // ============================================================

  Future<_TelegramDownloadChunk> _downloadChunk({
    required int initialDcId,
    required int slot,
    required t.InputFileLocationBase location,
    required int offset,
    required int limit,
  }) async {
    int dcId =
        initialDcId;

    int migrationCount =
        0;

    while (true) {
      final client =
          await _telegramClient
              .getDownloadClientForDataCenter(
        dcId,
        slot,
      );

      final response =
          await client.upload.getFile(
        precise:
            false,
        cdnSupported:
            false,
        location:
            location,
        offset:
            offset,
        limit:
            limit,
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

          if (migrationCount > 3) {
            throw Exception(
              'Too many Telegram DC migrations.',
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
          'Telegram returned an empty file response.',
        );
      }

      return _TelegramDownloadChunk(
        offset:
            offset,
        bytes:
            _readBytes(
          result,
        ),
        dcId:
            dcId,
      );
    }
  }

  // ============================================================
  // RESPONSE BYTES
  // ============================================================

  Uint8List _readBytes(
    dynamic result,
  ) {
    try {
      final dynamic rawBytes =
          result.bytes;

      if (rawBytes is Uint8List) {
        return rawBytes;
      }

      return Uint8List.fromList(
        List<int>.from(
          rawBytes as List,
        ),
      );
    } catch (_) {
      throw Exception(
        'Unsupported Telegram file response.',
      );
    }
  }

  // ============================================================
  // DC MIGRATION
  // ============================================================

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
}

// ============================================================
// DOWNLOAD CHUNK
// ============================================================

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

// ============================================================
// RESUME STATE
// ============================================================

class _ResumeState {
  final bool canResume;

  final int committedBytes;

  const _ResumeState({
    required this.canResume,
    required this.committedBytes,
  });
}

// ============================================================
// RESUME METADATA
// ============================================================

class _ResumeMetadata {
  final int version;

  final String resumeKey;

  final int expectedSize;

  final int chunkSize;

  final int committedBytes;

  const _ResumeMetadata({
    required this.version,
    required this.resumeKey,
    required this.expectedSize,
    required this.chunkSize,
    required this.committedBytes,
  });
}

// ============================================================
// RANDOM ACCESS WRITER
// ============================================================

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

  Future<void> truncate(
    int length,
  ) {
    final operation =
        _tail.then(
      (_) async {
        await _file.truncate(
          length,
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