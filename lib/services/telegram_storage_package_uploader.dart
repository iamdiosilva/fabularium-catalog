import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/telegram_storage_channel.dart';
import '../models/telegram_storage_package.dart';
import 'telegram_storage_packager.dart';
import 'telegram_storage_service.dart';

typedef TelegramStoragePackageUploadProgressCallback =
    void Function(
  TelegramStoragePackageUploadProgress progress,
);

class TelegramStoragePackageUploader {
  TelegramStoragePackageUploader._();

  static final TelegramStoragePackageUploader instance =
      TelegramStoragePackageUploader._();

  final TelegramStorageService _storage =
      TelegramStorageService.instance;

  final TelegramStoragePackager _packager =
      TelegramStoragePackager.instance;

  // ============================================================
  // UPLOAD PACKAGE
  // ============================================================

  Future<TelegramStoragePackageUploadResult>
      uploadPackage({
    required TelegramStorageChannel channel,
    required TelegramStoragePackage package,
    TelegramStoragePackageUploadProgressCallback?
        onProgress,
  }) async {
    if (package.parts.isEmpty) {
      throw const TelegramStoragePackageUploadException(
        'The prepared package contains no files.',
      );
    }

    /*
     * Se este pacote já foi completamente
     * enviado anteriormente, retornamos o receipt.
     *
     * Isso evita duplicar tudo no canal caso o
     * usuário pressione Upload novamente.
     */
    final completedReceipt =
        await _loadCompletedReceipt(
      package,
      channel,
    );

    if (completedReceipt != null) {
      _report(
        onProgress,
        overallProgress: 1,
        stage:
            'Package is already stored in Telegram.',
        currentPart: package.partCount,
        totalParts: package.partCount,
      );

      return TelegramStoragePackageUploadResult(
        packageId:
            package.packageId,
        channelId:
            channel.id,
        channelTitle:
            channel.title,
        partMessageIds:
            completedReceipt.partMessageIds,
        manifestMessageId:
            completedReceipt.manifestMessageId,
        uploadedPartsNow:
            0,
        reusedParts:
            package.partCount,
        alreadyUploaded:
            true,
        receiptPath:
            completedReceipt.receiptPath,
      );
    }

    await _validateLocalPackage(
      package,
    );

    /*
     * Recupera messageIds já registrados no
     * manifest.
     *
     * Eles só são reutilizados se o manifest
     * pertence ao mesmo canal configurado.
     */
    final manifestState =
        await _loadManifestState(
      package,
    );

    final messageIds =
        <int, int?>{};

    if (manifestState.channelId ==
        channel.id) {
      messageIds.addAll(
        manifestState.messageIds,
      );
    }

    /*
     * Já escrevemos o canal no manifest antes
     * de começar.
     */
    await _packager.writeManifest(
      package,
      channelId:
          channel.id,
      channelTitle:
          channel.title,
      messageIds:
          messageIds,
    );

    final totalPartBytes =
        package.parts.fold<int>(
      0,
      (
        total,
        part,
      ) =>
          total + part.size,
    );

    if (totalPartBytes <= 0) {
      throw const TelegramStoragePackageUploadException(
        'The storage package has an invalid total size.',
      );
    }

    int completedBytes =
        0;

    int uploadedPartsNow =
        0;

    int reusedParts =
        0;

    final sortedParts =
        List<TelegramStoragePackagePart>.from(
      package.parts,
    )
          ..sort(
            (
              a,
              b,
            ) =>
                a.index.compareTo(
              b.index,
            ),
          );

    // ==========================================================
    // UPLOAD PARTS
    // ==========================================================

    for (int listIndex = 0;
        listIndex < sortedParts.length;
        listIndex++) {
      final part =
          sortedParts[listIndex];

      final existingMessageId =
          messageIds[part.index];

      /*
       * Uma parte com messageId válido já foi
       * enviada em tentativa anterior.
       */
      if (existingMessageId != null &&
          existingMessageId > 0) {
        completedBytes +=
            part.size;

        reusedParts++;

        final overall =
            (
              completedBytes /
                  totalPartBytes
            ) *
                0.95;

        _report(
          onProgress,
          overallProgress:
              overall,
          stage:
              'Part ${part.index}/${package.partCount} already uploaded.',
          currentPart:
              part.index,
          totalParts:
              package.partCount,
          currentFileName:
              part.fileName,
          currentFileProgress:
              1,
        );

        continue;
      }

      final partFile =
          File(
        part.filePath,
      );

      if (!await partFile.exists()) {
        throw TelegramStoragePackageUploadException(
          'Storage part not found: ${part.fileName}',
        );
      }

      final actualSize =
          await partFile.length();

      if (actualSize !=
          part.size) {
        throw TelegramStoragePackageUploadException(
          'Storage part changed after packaging: '
          '${part.fileName}',
        );
      }

      _report(
        onProgress,
        overallProgress:
            completedBytes /
                totalPartBytes *
                0.95,
        stage:
            'Uploading part ${part.index}/${package.partCount}...',
        currentPart:
            part.index,
        totalParts:
            package.partCount,
        currentFileName:
            part.fileName,
        currentFileProgress:
            0,
      );

      final uploadResult =
          await _storage.uploadFile(
        channel:
            channel,
        filePath:
            part.filePath,
        onProgress:
            (
          partProgress,
        ) {
          final bytesInsidePart =
              part.size *
                  partProgress;

          final overall =
              (
                    completedBytes +
                        bytesInsidePart
                  ) /
                  totalPartBytes *
                  0.95;

          _report(
            onProgress,
            overallProgress:
                overall,
            stage:
                'Uploading part ${part.index}/${package.partCount}...',
            currentPart:
                part.index,
            totalParts:
                package.partCount,
            currentFileName:
                part.fileName,
            currentFileProgress:
                partProgress,
          );
        },
      );

      final messageId =
          uploadResult.messageId;

      if (messageId == null ||
          messageId <= 0) {
        throw TelegramStoragePackageUploadException(
          'Telegram uploaded ${part.fileName}, '
          'but no message ID was returned.',
        );
      }

      messageIds[part.index] =
          messageId;

      completedBytes +=
          part.size;

      uploadedPartsNow++;

      /*
       * Persistimos imediatamente depois de cada
       * upload.
       *
       * Se o app fechar depois daqui, a próxima
       * tentativa consegue pular essa parte.
       */
      await _packager.writeManifest(
        package,
        channelId:
            channel.id,
        channelTitle:
            channel.title,
        messageIds:
            messageIds,
      );

      _report(
        onProgress,
        overallProgress:
            completedBytes /
                totalPartBytes *
                0.95,
        stage:
            'Part ${part.index}/${package.partCount} uploaded.',
        currentPart:
            part.index,
        totalParts:
            package.partCount,
        currentFileName:
            part.fileName,
        currentFileProgress:
            1,
      );
    }

    // ==========================================================
    // FINAL MANIFEST
    // ==========================================================

    /*
     * Garantimos uma última escrita antes de
     * publicar o manifest.
     */
    await _packager.writeManifest(
      package,
      channelId:
          channel.id,
      channelTitle:
          channel.title,
      messageIds:
          messageIds,
    );

    final manifestFile =
        File(
      package.manifestPath,
    );

    if (!await manifestFile.exists()) {
      throw const TelegramStoragePackageUploadException(
        'Package manifest no longer exists.',
      );
    }

    _report(
      onProgress,
      overallProgress:
          0.95,
      stage:
          'Uploading final manifest...',
      currentPart:
          package.partCount,
      totalParts:
          package.partCount,
      currentFileName:
          p.basename(
        package.manifestPath,
      ),
      currentFileProgress:
          0,
    );

    final manifestUpload =
        await _storage.uploadFile(
      channel:
          channel,
      filePath:
          package.manifestPath,
      onProgress:
          (
        progress,
      ) {
        /*
         * Manifest ocupa os últimos 5%.
         */
        final overall =
            0.95 +
                (
                  progress *
                      0.05
                );

        _report(
          onProgress,
          overallProgress:
              overall,
          stage:
              'Uploading final manifest...',
          currentPart:
              package.partCount,
          totalParts:
              package.partCount,
          currentFileName:
              p.basename(
            package.manifestPath,
          ),
          currentFileProgress:
              progress,
        );
      },
    );

    final manifestMessageId =
        manifestUpload.messageId;

    if (manifestMessageId == null ||
        manifestMessageId <= 0) {
      throw const TelegramStoragePackageUploadException(
        'The manifest was uploaded, but Telegram '
        'did not return its message ID.',
      );
    }

    // ==========================================================
    // LOCAL RECEIPT
    // ==========================================================

    final receiptPath =
        await _writeReceipt(
      package:
          package,
      channel:
          channel,
      partMessageIds:
          messageIds,
      manifestMessageId:
          manifestMessageId,
    );

    _report(
      onProgress,
      overallProgress:
          1,
      stage:
          'Package stored successfully.',
      currentPart:
          package.partCount,
      totalParts:
          package.partCount,
      currentFileName:
          p.basename(
        package.manifestPath,
      ),
      currentFileProgress:
          1,
    );

    return TelegramStoragePackageUploadResult(
      packageId:
          package.packageId,
      channelId:
          channel.id,
      channelTitle:
          channel.title,
      partMessageIds:
          Map<int, int>.fromEntries(
        messageIds.entries
            .where(
              (
                entry,
              ) =>
                  entry.value != null &&
                  entry.value! > 0,
            )
            .map(
              (
                entry,
              ) =>
                  MapEntry<int, int>(
                entry.key,
                entry.value!,
              ),
            ),
      ),
      manifestMessageId:
          manifestMessageId,
      uploadedPartsNow:
          uploadedPartsNow,
      reusedParts:
          reusedParts,
      alreadyUploaded:
          false,
      receiptPath:
          receiptPath,
    );
  }

  // ============================================================
  // VALIDATION
  // ============================================================

  Future<void> _validateLocalPackage(
    TelegramStoragePackage package,
  ) async {
    final staging =
        Directory(
      package.stagingDirectoryPath,
    );

    if (!await staging.exists()) {
      throw const TelegramStoragePackageUploadException(
        'The package staging folder no longer exists.',
      );
    }

    for (final part
        in package.parts) {
      final file =
          File(
        part.filePath,
      );

      if (!await file.exists()) {
        throw TelegramStoragePackageUploadException(
          'Missing storage part: ${part.fileName}',
        );
      }

      final length =
          await file.length();

      if (length !=
          part.size) {
        throw TelegramStoragePackageUploadException(
          'Storage part size changed: ${part.fileName}',
        );
      }
    }
  }

  // ============================================================
  // READ MANIFEST STATE
  // ============================================================

  Future<_TelegramStorageManifestState>
      _loadManifestState(
    TelegramStoragePackage package,
  ) async {
    final file =
        File(
      package.manifestPath,
    );

    if (!await file.exists()) {
      return const _TelegramStorageManifestState(
        channelId:
            null,
        messageIds:
            <int, int?>{},
      );
    }

    try {
      final decoded =
          jsonDecode(
        await file.readAsString(),
      );

      if (decoded is! Map) {
        throw const FormatException();
      }

      final root =
          Map<String, dynamic>.from(
        decoded,
      );

      int? channelId;

      final telegram =
          root['telegram'];

      if (telegram is Map) {
        final telegramMap =
            Map<String, dynamic>.from(
          telegram,
        );

        final rawChannelId =
            telegramMap['channelId'];

        if (rawChannelId is int) {
          channelId =
              rawChannelId;
        } else if (rawChannelId is num) {
          channelId =
              rawChannelId.toInt();
        }
      }

      final messageIds =
          <int, int?>{};

      final rawParts =
          root['parts'];

      if (rawParts is List) {
        for (final dynamic rawPart
            in rawParts) {
          if (rawPart is! Map) {
            continue;
          }

          final part =
              Map<String, dynamic>.from(
            rawPart,
          );

          final rawIndex =
              part['index'];

          final rawMessageId =
              part['messageId'];

          final index =
              rawIndex is int
                  ? rawIndex
                  : rawIndex is num
                      ? rawIndex.toInt()
                      : null;

          final messageId =
              rawMessageId is int
                  ? rawMessageId
                  : rawMessageId is num
                      ? rawMessageId.toInt()
                      : null;

          if (index == null ||
              index <= 0) {
            continue;
          }

          messageIds[index] =
              messageId;
        }
      }

      return _TelegramStorageManifestState(
        channelId:
            channelId,
        messageIds:
            messageIds,
      );
    } catch (_) {
      /*
       * Manifest inválido não deve fazer o
       * uploader confiar em IDs possivelmente
       * corrompidos.
       *
       * O packager vai reescrevê-lo.
       */
      return const _TelegramStorageManifestState(
        channelId:
            null,
        messageIds:
            <int, int?>{},
      );
    }
  }

  // ============================================================
  // RECEIPT
  // ============================================================

  String _receiptPath(
    TelegramStoragePackage package,
  ) {
    return p.join(
      package.stagingDirectoryPath,
      '${package.packageId}.upload.json',
    );
  }

  Future<String> _writeReceipt({
    required TelegramStoragePackage package,
    required TelegramStorageChannel channel,
    required Map<int, int?> partMessageIds,
    required int manifestMessageId,
  }) async {
    final file =
        File(
      _receiptPath(
        package,
      ),
    );

    final temp =
        File(
      '${file.path}.tmp',
    );

    final parts =
        package.parts
            .map(
              (
                part,
              ) =>
                  <String, dynamic>{
                'index':
                    part.index,
                'fileName':
                    part.fileName,
                'messageId':
                    partMessageIds[
                      part.index
                    ],
              },
            )
            .toList();

    final encoder =
        const JsonEncoder.withIndent(
      '  ',
    );

    await temp.writeAsString(
      encoder.convert(
        <String, dynamic>{
          'version':
              1,
          'kind':
              'fabularium-storage-upload-receipt',
          'packageId':
              package.packageId,
          'completedAt':
              DateTime.now()
                  .toUtc()
                  .toIso8601String(),
          'channel':
              <String, dynamic>{
            'id':
                channel.id,
            'title':
                channel.title,
          },
          'manifest':
              <String, dynamic>{
            'fileName':
                p.basename(
              package.manifestPath,
            ),
            'messageId':
                manifestMessageId,
          },
          'parts':
              parts,
        },
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

    return file.path;
  }

  Future<_TelegramStorageCompletedReceipt?>
      _loadCompletedReceipt(
    TelegramStoragePackage package,
    TelegramStorageChannel channel,
  ) async {
    final file =
        File(
      _receiptPath(
        package,
      ),
    );

    try {
      if (!await file.exists()) {
        return null;
      }

      final decoded =
          jsonDecode(
        await file.readAsString(),
      );

      if (decoded is! Map) {
        return null;
      }

      final root =
          Map<String, dynamic>.from(
        decoded,
      );

      if (root['version'] != 1 ||
          root['packageId'] !=
              package.packageId) {
        return null;
      }

      final rawChannel =
          root['channel'];

      if (rawChannel is! Map) {
        return null;
      }

      final channelMap =
          Map<String, dynamic>.from(
        rawChannel,
      );

      final rawChannelId =
          channelMap['id'];

      final receiptChannelId =
          rawChannelId is int
              ? rawChannelId
              : rawChannelId is num
                  ? rawChannelId.toInt()
                  : null;

      if (receiptChannelId !=
          channel.id) {
        return null;
      }

      final rawManifest =
          root['manifest'];

      if (rawManifest is! Map) {
        return null;
      }

      final manifestMap =
          Map<String, dynamic>.from(
        rawManifest,
      );

      final rawManifestMessageId =
          manifestMap['messageId'];

      final manifestMessageId =
          rawManifestMessageId is int
              ? rawManifestMessageId
              : rawManifestMessageId is num
                  ? rawManifestMessageId
                      .toInt()
                  : null;

      if (manifestMessageId == null ||
          manifestMessageId <= 0) {
        return null;
      }

      final ids =
          <int, int>{};

      final rawParts =
          root['parts'];

      if (rawParts is! List) {
        return null;
      }

      for (final dynamic rawPart
          in rawParts) {
        if (rawPart is! Map) {
          continue;
        }

        final part =
            Map<String, dynamic>.from(
          rawPart,
        );

        final rawIndex =
            part['index'];

        final rawMessageId =
            part['messageId'];

        final index =
            rawIndex is int
                ? rawIndex
                : rawIndex is num
                    ? rawIndex.toInt()
                    : null;

        final messageId =
            rawMessageId is int
                ? rawMessageId
                : rawMessageId is num
                    ? rawMessageId.toInt()
                    : null;

        if (index == null ||
            index <= 0 ||
            messageId == null ||
            messageId <= 0) {
          continue;
        }

        ids[index] =
            messageId;
      }

      /*
       * Receipt só é considerado completo
       * quando TODAS as partes possuem ID.
       */
      for (final part
          in package.parts) {
        if (!ids.containsKey(
          part.index,
        )) {
          return null;
        }
      }

      return _TelegramStorageCompletedReceipt(
        receiptPath:
            file.path,
        manifestMessageId:
            manifestMessageId,
        partMessageIds:
            ids,
      );
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // PROGRESS
  // ============================================================

  void _report(
    TelegramStoragePackageUploadProgressCallback?
        callback, {
    required double overallProgress,
    required String stage,
    required int currentPart,
    required int totalParts,
    String? currentFileName,
    double currentFileProgress = 0,
  }) {
    callback?.call(
      TelegramStoragePackageUploadProgress(
        overallProgress:
            overallProgress
                .clamp(
                  0.0,
                  1.0,
                )
                .toDouble(),
        stage:
            stage,
        currentPart:
            currentPart,
        totalParts:
            totalParts,
        currentFileName:
            currentFileName,
        currentFileProgress:
            currentFileProgress
                .clamp(
                  0.0,
                  1.0,
                )
                .toDouble(),
      ),
    );
  }
}

// ============================================================
// PROGRESS
// ============================================================

class TelegramStoragePackageUploadProgress {
  final double overallProgress;

  final String stage;

  final int currentPart;

  final int totalParts;

  final String? currentFileName;

  final double currentFileProgress;

  const TelegramStoragePackageUploadProgress({
    required this.overallProgress,
    required this.stage,
    required this.currentPart,
    required this.totalParts,
    required this.currentFileName,
    required this.currentFileProgress,
  });
}

// ============================================================
// RESULT
// ============================================================

class TelegramStoragePackageUploadResult {
  final String packageId;

  final int channelId;

  final String channelTitle;

  final Map<int, int> partMessageIds;

  final int manifestMessageId;

  final int uploadedPartsNow;

  final int reusedParts;

  final bool alreadyUploaded;

  final String receiptPath;

  const TelegramStoragePackageUploadResult({
    required this.packageId,
    required this.channelId,
    required this.channelTitle,
    required this.partMessageIds,
    required this.manifestMessageId,
    required this.uploadedPartsNow,
    required this.reusedParts,
    required this.alreadyUploaded,
    required this.receiptPath,
  });
}

// ============================================================
// INTERNAL STATE
// ============================================================

class _TelegramStorageManifestState {
  final int? channelId;

  final Map<int, int?> messageIds;

  const _TelegramStorageManifestState({
    required this.channelId,
    required this.messageIds,
  });
}

class _TelegramStorageCompletedReceipt {
  final String receiptPath;

  final int manifestMessageId;

  final Map<int, int> partMessageIds;

  const _TelegramStorageCompletedReceipt({
    required this.receiptPath,
    required this.manifestMessageId,
    required this.partMessageIds,
  });
}

// ============================================================
// EXCEPTION
// ============================================================

class TelegramStoragePackageUploadException
    implements Exception {
  final String message;

  const TelegramStoragePackageUploadException(
    this.message,
  );

  @override
  String toString() =>
      message;
}