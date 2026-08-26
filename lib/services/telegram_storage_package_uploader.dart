import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../models/telegram_storage_package.dart';
import '../models/telegram_storage_upload_journal.dart';
import '../models/telegram_storage_workspace.dart';
import 'telegram_storage_media_group_service.dart';
import 'telegram_storage_upload_journal_service.dart';

typedef TelegramStoragePackageUploadProgressCallback =
    void Function(
  TelegramStoragePackageUploadProgress progress,
);

class TelegramStoragePackageUploader {
  TelegramStoragePackageUploader._();

  static final TelegramStoragePackageUploader instance =
      TelegramStoragePackageUploader._();

  final TelegramStorageMediaGroupService _mediaGroups =
      TelegramStorageMediaGroupService.instance;

  final TelegramStorageUploadJournalService _journalService =
      TelegramStorageUploadJournalService.instance;

  /*
   * Agora o manifest é enviado DEPOIS das partes.
   *
   * Portanto cada grupo pode usar os 10 slots
   * disponíveis para arquivos.
   */
  static const int _partsPerDocumentGroup =
      10;

  // ============================================================
  // UPLOAD
  // ============================================================

  Future<TelegramStoragePackageUploadResult>
      uploadPackage({
    required TelegramStorageWorkspace workspace,
    required TelegramStoragePackage package,
    TelegramStoragePackageUploadProgressCallback?
        onProgress,
  }) async {
    final catalogChannel =
        workspace.catalogChannel;

    final filesChannel =
        workspace.filesChannel;

    if (catalogChannel == null ||
        filesChannel == null) {
      throw const TelegramStoragePackageUploadException(
        'Configure both Catalog Channel and Files Channel '
        'before uploading a package.',
      );
    }

    if (catalogChannel.id ==
        filesChannel.id) {
      throw const TelegramStoragePackageUploadException(
        'Catalog Channel and Files Channel must be different.',
      );
    }

    if (package.parts.isEmpty) {
      throw const TelegramStoragePackageUploadException(
        'The prepared package contains no files.',
      );
    }

    await _validateLocalPackage(
      package,
    );

    final plans =
        _createFileGroupPlans(
      package,
    );

    // ==========================================================
    // JOURNAL
    // ==========================================================

    var journal =
        await _journalService.load(
      package.packageId,
    );

    if (journal != null) {
      if (journal.catalogChannel.id !=
              catalogChannel.id ||
          journal.filesChannel.id !=
              filesChannel.id) {
        throw const TelegramStoragePackageUploadException(
          'This package already has an upload journal '
          'linked to different Telegram channels.',
        );
      }
    }

    journal ??=
        TelegramStorageUploadJournal(
      packageId:
          package.packageId,
      modelName:
          package.displayName,
      stagingDirectoryPath:
          package.stagingDirectoryPath,
      catalogChannel:
          catalogChannel,
      filesChannel:
          filesChannel,
      status:
          TelegramStorageUploadStatus.preparing,
      createdAt:
          DateTime.now(),
      updatedAt:
          DateTime.now(),
      galleryGroupedId:
          null,
      galleryMessageIds:
          const <int>[],
      fileGroups:
          <int, TelegramStorageUploadJournalGroup>{},
      manifestMessageId:
          null,
      lastError:
          null,
    );

    await _journalService.save(
      journal,
    );

    // ==========================================================
    // ALREADY STORED
    // ==========================================================

    if (_isJournalComplete(
      journal:
          journal,
      package:
          package,
      plans:
          plans,
    )) {
      return _buildResult(
        package:
            package,
        journal:
            journal,
        uploadedPartsNow:
            0,
        reusedParts:
            package.partCount,
        alreadyUploaded:
            true,
      );
    }

    journal =
        await _journalService.markUploading(
      journal,
    );

    int uploadedPartsNow = 0;

    int reusedParts = 0;

    try {
      // ========================================================
      // 1. CATALOG GALLERY
      // ========================================================

      final galleryPaths =
          package.galleryImagePaths;

      if (galleryPaths.isNotEmpty) {
        final galleryComplete =
            journal.galleryMessageIds.length ==
                galleryPaths.length;

        if (!galleryComplete) {
          _report(
            onProgress,
            overallProgress:
                0,
            stage:
                'Uploading catalog gallery...',
            currentPart:
                0,
            totalParts:
                package.partCount,
            currentFileName:
                null,
            currentFileProgress:
                0,
          );

          final galleryItems =
              <TelegramStorageMediaItem>[];

          final caption =
              _buildGalleryCaption(
            package,
          );

          for (int index = 0;
              index < galleryPaths.length;
              index++) {
            final imagePath =
                galleryPaths[index];

            galleryItems.add(
              TelegramStorageMediaItem(
                kind:
                    TelegramStorageMediaKind.photo,
                filePath:
                    imagePath,
                fileName:
                    p.basename(
                  imagePath,
                ),
                mimeType:
                    _mimeTypeForImage(
                  imagePath,
                ),
                caption:
                    index == 0
                        ? caption
                        : '',
                randomIdKey:
                    '${package.packageId}'
                    ':catalog:gallery:$index',
              ),
            );
          }

          final galleryResult =
              await _mediaGroups.sendGroup(
            channel:
                catalogChannel,
            items:
                galleryItems,
            onProgress:
                (
              progress,
              stage,
            ) {
              _report(
                onProgress,
                overallProgress:
                    progress *
                        0.10,
                stage:
                    stage,
                currentPart:
                    0,
                totalParts:
                    package.partCount,
                currentFileName:
                    null,
                currentFileProgress:
                    progress,
              );
            },
          );

          journal =
              journal.copyWith(
            galleryGroupedId:
                galleryResult.groupedId,
            galleryMessageIds:
                galleryResult.messageIds,
          );

          await _journalService.save(
            journal,
          );
        }
      }

      // ========================================================
      // 2. FILE GROUPS
      // ========================================================

      final totalFileBytes =
          package.parts.fold<int>(
        0,
        (
          total,
          part,
        ) =>
            total +
            part.size,
      );

      int completedFileBytes = 0;

      for (final plan
          in plans) {
        final existing =
            journal?.fileGroups[
              plan.groupIndex
            ];

        // ======================================================
        // ALREADY COMPLETED GROUP
        // ======================================================

        if (_isFileGroupComplete(
          plan:
              plan,
          journalGroup:
              existing,
        )) {
          reusedParts +=
              plan.parts.length;

          completedFileBytes +=
              plan.parts.fold<int>(
            0,
            (
              total,
              part,
            ) =>
                total +
                part.size,
          );

          continue;
        }

        final groupBytes =
            plan.parts.fold<int>(
          0,
          (
            total,
            part,
          ) =>
              total +
              part.size,
        );

        final bytesBeforeGroup =
            completedFileBytes;

        final caption =
            _buildFilesCaption(
          package:
              package,
          groupIndex:
              plan.groupIndex,
          totalGroups:
              plans.length,
        );

        final items =
            <TelegramStorageMediaItem>[];

        for (int index = 0;
            index < plan.parts.length;
            index++) {
          final part =
              plan.parts[index];

          items.add(
            TelegramStorageMediaItem(
              kind:
                  TelegramStorageMediaKind.document,
              filePath:
                  part.filePath,
              fileName:
                  part.fileName,
              mimeType:
                  'application/octet-stream',
              caption:
                  index == 0
                      ? caption
                      : '',
              randomIdKey:
                  '${package.packageId}'
                  ':storage'
                  ':group:${plan.groupIndex}'
                  ':part:${part.index}',
            ),
          );
        }

        _report(
          onProgress,
          overallProgress:
              _mapFilesProgress(
            completedFileBytes,
            totalFileBytes,
          ),
          stage:
              'Uploading files '
              '${plan.groupIndex}/${plans.length}...',
          currentPart:
              plan.parts.first.index,
          totalParts:
              package.partCount,
          currentFileName:
              plan.parts.first.fileName,
          currentFileProgress:
              0,
        );

        final result =
            await _mediaGroups.sendGroup(
          channel:
              filesChannel,
          items:
              items,
          onProgress:
              (
            progress,
            stage,
          ) {
            final estimatedBytes =
                bytesBeforeGroup +
                    (
                      groupBytes *
                          progress
                    );

            _report(
              onProgress,
              overallProgress:
                  _mapFilesProgress(
                estimatedBytes,
                totalFileBytes,
              ),
              stage:
                  stage,
              currentPart:
                  plan.parts.first.index,
              totalParts:
                  package.partCount,
              currentFileName:
                  plan.parts.first.fileName,
              currentFileProgress:
                  progress,
            );
          },
        );

        if (result.messageIds.length !=
            plan.parts.length) {
          throw const TelegramStoragePackageUploadException(
            'Telegram returned an incomplete file group.',
          );
        }

        final partMessageIds =
            <int, int>{};

        for (int index = 0;
            index < plan.parts.length;
            index++) {
          final part =
              plan.parts[index];

          partMessageIds[
              part.index] =
              result.messageIds[index];
        }

        final updatedGroups =
            Map<int,
                TelegramStorageUploadJournalGroup>.from(
          journal!.fileGroups,
        );

        updatedGroups[
            plan.groupIndex] =
            TelegramStorageUploadJournalGroup(
          groupIndex:
              plan.groupIndex,
          groupedId:
              result.groupedId,
          messageIds:
              result.messageIds,
          partMessageIds:
              partMessageIds,
        );

        journal =
            journal.copyWith(
          fileGroups:
              updatedGroups,
        );

        /*
         * IMPORTANT:
         *
         * cada grupo é persistido imediatamente.
         *
         * Se o próximo grupo falhar, este grupo
         * não será reenviado no retry.
         */
        await _journalService.save(
          journal,
        );

        uploadedPartsNow +=
            plan.parts.length;

        completedFileBytes +=
            groupBytes;
      }

      // ========================================================
      // 3. FINAL MANIFEST V3
      // ========================================================

      if (!journal!.hasManifest) {
        _report(
          onProgress,
          overallProgress:
              0.95,
          stage:
              'Creating final manifest...',
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

        await _writeManifestV3(
          package:
              package,
          journal:
              journal,
        );

        final manifestItem =
            TelegramStorageMediaItem(
          kind:
              TelegramStorageMediaKind.document,
          filePath:
              package.manifestPath,
          fileName:
              p.basename(
            package.manifestPath,
          ),
          mimeType:
              'application/json',
          caption:
              _buildManifestCaption(
            package,
          ),
          randomIdKey:
              '${package.packageId}'
              ':storage:manifest:v3',
        );

        final manifestResult =
            await _mediaGroups.sendGroup(
          channel:
              filesChannel,
          items:
              <TelegramStorageMediaItem>[
            manifestItem,
          ],
          onProgress:
              (
            progress,
            stage,
          ) {
            _report(
              onProgress,
              overallProgress:
                  0.95 +
                      (
                        progress *
                            0.05
                      ),
              stage:
                  stage,
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

        if (manifestResult.messageIds.length !=
            1) {
          throw const TelegramStoragePackageUploadException(
            'Telegram did not return the manifest message ID.',
          );
        }

        journal =
            journal.copyWith(
          manifestMessageId:
              manifestResult.messageIds.single,
        );

        await _journalService.save(
          journal,
        );
      }

      // ========================================================
      // 4. STORED
      // ========================================================

      journal =
          await _journalService.markStored(
        journal,
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
            null,
        currentFileProgress:
            1,
      );

      return _buildResult(
        package:
            package,
        journal:
            journal,
        uploadedPartsNow:
            uploadedPartsNow,
        reusedParts:
            reusedParts,
        alreadyUploaded:
            false,
      );
    } catch (error) {
      try {
        journal =
            await _journalService.markFailed(
          journal!,
          error,
        );
      } catch (_) {}

      rethrow;
    }
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

    for (final imagePath
        in package.galleryImagePaths) {
      if (!await File(
        imagePath,
      ).exists()) {
        throw TelegramStoragePackageUploadException(
          'Gallery image no longer exists: '
          '${p.basename(imagePath)}',
        );
      }
    }
  }

  // ============================================================
  // GROUP PLAN
  // ============================================================

  List<_FileGroupPlan>
      _createFileGroupPlans(
    TelegramStoragePackage package,
  ) {
    final sorted =
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

    final result =
        <_FileGroupPlan>[];

    int offset = 0;

    int groupIndex = 1;

    while (offset <
        sorted.length) {
      final remaining =
          sorted.length -
              offset;

      final count =
          min<int>(
        _partsPerDocumentGroup,
        remaining,
      );

      result.add(
        _FileGroupPlan(
          groupIndex:
              groupIndex,
          parts:
              sorted.sublist(
            offset,
            offset +
                count,
          ),
        ),
      );

      offset +=
          count;

      groupIndex++;
    }

    return result;
  }

  // ============================================================
  // JOURNAL VALIDATION
  // ============================================================

  bool _isFileGroupComplete({
    required _FileGroupPlan plan,
    required TelegramStorageUploadJournalGroup?
        journalGroup,
  }) {
    if (journalGroup == null) {
      return false;
    }

    if (journalGroup.messageIds.length !=
        plan.parts.length) {
      return false;
    }

    for (final messageId
        in journalGroup.messageIds) {
      if (messageId <= 0) {
        return false;
      }
    }

    for (final part
        in plan.parts) {
      final messageId =
          journalGroup.partMessageIds[
            part.index
          ];

      if (messageId == null ||
          messageId <= 0) {
        return false;
      }
    }

    return true;
  }

  bool _isJournalComplete({
    required TelegramStorageUploadJournal journal,
    required TelegramStoragePackage package,
    required List<_FileGroupPlan> plans,
  }) {
    if (!journal.isStored ||
        !journal.hasManifest) {
      return false;
    }

    if (package.galleryImagePaths.isNotEmpty &&
        journal.galleryMessageIds.length !=
            package.galleryImagePaths.length) {
      return false;
    }

    for (final plan
        in plans) {
      if (!_isFileGroupComplete(
        plan:
            plan,
        journalGroup:
            journal.fileGroups[
              plan.groupIndex
            ],
      )) {
        return false;
      }
    }

    return true;
  }

  // ============================================================
  // MANIFEST V3
  // ============================================================

  Future<void> _writeManifestV3({
    required TelegramStoragePackage package,
    required TelegramStorageUploadJournal journal,
  }) async {
    final partMessageIds =
        <int, int>{};

    final groups =
        journal.fileGroups.values
            .toList()
          ..sort(
            (
              a,
              b,
            ) =>
                a.groupIndex.compareTo(
              b.groupIndex,
            ),
          );

    for (final group
        in groups) {
      partMessageIds.addAll(
        group.partMessageIds,
      );
    }

    final parts =
        package.parts
            .map(
              (
                part,
              ) =>
                  <String, dynamic>{
                ...part.toManifestJson(),
                'messageId':
                    partMessageIds[
                      part.index
                    ],
              },
            )
            .toList();

    final root =
        <String, dynamic>{
      'version':
          3,

      'kind':
          'fabularium-storage-package',

      'packageId':
          package.packageId,

      'createdAt':
          package.createdAt
              .toUtc()
              .toIso8601String(),

      // ========================================================
      // CATALOG
      // ========================================================

      'catalog':
          package.catalog
                  ?.toManifestJson() ??
              <String, dynamic>{
                'name':
                    package.sourceFolderName,
              },

      // ========================================================
      // SOURCE
      // ========================================================

      'source':
          <String, dynamic>{
        'folderName':
            package.sourceFolderName,
        'size':
            package.sourceSize,
      },

      // ========================================================
      // ARCHIVE
      // ========================================================

      'archive':
          <String, dynamic>{
        'fileName':
            package.archiveFileName,
        'size':
            package.archiveSize,
        'sha256':
            package.archiveSha256,
        'split':
            package.isSplit,
        'partCount':
            package.partCount,
      },

      // ========================================================
      // TELEGRAM
      // ========================================================

      'telegram':
          <String, dynamic>{
        'catalogChannel':
            <String, dynamic>{
          'id':
              journal.catalogChannel.id,
          'title':
              journal.catalogChannel.title,
        },

        'filesChannel':
            <String, dynamic>{
          'id':
              journal.filesChannel.id,
          'title':
              journal.filesChannel.title,
        },

        'gallery':
            <String, dynamic>{
          'groupedId':
              journal.galleryGroupedId,
          'messageIds':
              journal.galleryMessageIds,
        },

        'fileGroups':
            groups
                .map(
                  (
                    group,
                  ) =>
                      <String, dynamic>{
                    'groupIndex':
                        group.groupIndex,
                    'groupedId':
                        group.groupedId,
                    'messageIds':
                        group.messageIds,
                  },
                )
                .toList(),
      },

      // ========================================================
      // PARTS
      // ========================================================

      'parts':
          parts,
    };

    final file =
        File(
      package.manifestPath,
    );

    await file.parent.create(
      recursive:
          true,
    );

    final temp =
        File(
      '${file.path}.tmp',
    );

    const encoder =
        JsonEncoder.withIndent(
      '  ',
    );

    await temp.writeAsString(
      encoder.convert(
        root,
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
  }

  // ============================================================
  // CAPTIONS
  // ============================================================

  String _buildGalleryCaption(
    TelegramStoragePackage package,
  ) {
    final catalog =
        package.catalog;

    final buffer =
        StringBuffer();

    buffer.writeln(
      '[FABULARIUM:${package.packageId}]',
    );

    buffer.writeln();

    buffer.writeln(
      '🖼 ${package.displayName}',
    );

    if (catalog?.studio !=
        null) {
      buffer.writeln(
        'Studio: ${catalog!.studio}',
      );
    }

    if (catalog?.category !=
        null) {
      buffer.writeln(
        'Category: ${catalog!.category}',
      );
    }

    if (catalog?.type !=
        null) {
      buffer.writeln(
        'Type: ${catalog!.type}',
      );
    }

    if (catalog?.scale !=
        null) {
      buffer.writeln(
        'Scale: ${catalog!.scale}',
      );
    }

    if (catalog?.height !=
        null) {
      buffer.writeln(
        'Height: ${catalog!.height}',
      );
    }

    buffer.writeln();

    buffer.writeln(
      'Archive: ${_formatBytes(package.archiveSize)}',
    );

    buffer.writeln(
      'Parts: ${package.partCount}',
    );

    final description =
        catalog?.description
            ?.trim();

    if (description != null &&
        description.isNotEmpty) {
      buffer.writeln();

      final shortened =
          description.length >
                  350
              ? '${description.substring(0, 347)}...'
              : description;

      buffer.write(
        shortened,
      );
    }

    final result =
        buffer
            .toString()
            .trim();

    if (result.length <=
        900) {
      return result;
    }

    return result.substring(
      0,
      900,
    );
  }

  String _buildFilesCaption({
    required TelegramStoragePackage package,
    required int groupIndex,
    required int totalGroups,
  }) {
    final buffer =
        StringBuffer();

    buffer.writeln(
      '[FABULARIUM:${package.packageId}]',
    );

    buffer.writeln();

    buffer.writeln(
      '📦 ${package.displayName}',
    );

    if (totalGroups > 1) {
      buffer.writeln(
        'Files $groupIndex/$totalGroups',
      );
    } else {
      buffer.writeln(
        'Storage Files',
      );
    }

    return buffer
        .toString()
        .trim();
  }

  String _buildManifestCaption(
    TelegramStoragePackage package,
  ) {
    return '[FABULARIUM_MANIFEST:${package.packageId}]\n\n'
        '📋 ${package.displayName}\n'
        'Storage Manifest V3';
  }

  String _mimeTypeForImage(
    String path,
  ) {
    switch (
        p.extension(
          path,
        ).toLowerCase()) {
      case '.png':
        return 'image/png';

      case '.jpg':
      case '.jpeg':
      default:
        return 'image/jpeg';
    }
  }

  // ============================================================
  // PROGRESS
  // ============================================================

  double _mapFilesProgress(
    num bytes,
    int totalBytes,
  ) {
    if (totalBytes <= 0) {
      return 0.10;
    }

    final ratio =
        (
          bytes /
              totalBytes
        ).clamp(
          0.0,
          1.0,
        );

    /*
     * Gallery:
     * 0% - 10%
     *
     * Files:
     * 10% - 95%
     *
     * Manifest:
     * 95% - 100%
     */
    return 0.10 +
        (
          ratio *
              0.85
        );
  }

  void _report(
    TelegramStoragePackageUploadProgressCallback?
        callback, {
    required double overallProgress,
    required String stage,
    required int currentPart,
    required int totalParts,
    required String? currentFileName,
    required double currentFileProgress,
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

  // ============================================================
  // RESULT
  // ============================================================

  TelegramStoragePackageUploadResult
      _buildResult({
    required TelegramStoragePackage package,
    required TelegramStorageUploadJournal journal,
    required int uploadedPartsNow,
    required int reusedParts,
    required bool alreadyUploaded,
  }) {
    final partMessageIds =
        <int, int>{};

    final fileGroupedIds =
        <int>[];

    final groups =
        journal.fileGroups.values
            .toList()
          ..sort(
            (
              a,
              b,
            ) =>
                a.groupIndex.compareTo(
              b.groupIndex,
            ),
          );

    for (final group
        in groups) {
      partMessageIds.addAll(
        group.partMessageIds,
      );

      if (group.groupedId !=
          null) {
        fileGroupedIds.add(
          group.groupedId!,
        );
      }
    }

    final manifestMessageId =
        journal.manifestMessageId;

    if (manifestMessageId ==
        null) {
      throw const TelegramStoragePackageUploadException(
        'Storage upload completed without a manifest message ID.',
      );
    }

    return TelegramStoragePackageUploadResult(
      packageId:
          package.packageId,

      catalogChannelId:
          journal.catalogChannel.id,

      catalogChannelTitle:
          journal.catalogChannel.title,

      filesChannelId:
          journal.filesChannel.id,

      filesChannelTitle:
          journal.filesChannel.title,

      partMessageIds:
          partMessageIds,

      manifestMessageId:
          manifestMessageId,

      uploadedPartsNow:
          uploadedPartsNow,

      reusedParts:
          reusedParts,

      alreadyUploaded:
          alreadyUploaded,

      galleryMessageIds:
          journal.galleryMessageIds,

      galleryGroupedId:
          journal.galleryGroupedId,

      fileGroupedIds:
          fileGroupedIds,
    );
  }

  String _formatBytes(
    int bytes,
  ) {
    const int mb =
        1024 * 1024;

    const int gb =
        mb * 1024;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }

    return '${(bytes / mb).toStringAsFixed(2)} MB';
  }
}

// ============================================================
// GROUP PLAN
// ============================================================

class _FileGroupPlan {
  final int groupIndex;

  final List<TelegramStoragePackagePart> parts;

  const _FileGroupPlan({
    required this.groupIndex,
    required this.parts,
  });
}

// ============================================================
// PUBLIC PROGRESS
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
// PUBLIC RESULT
// ============================================================

class TelegramStoragePackageUploadResult {
  final String packageId;

  final int catalogChannelId;

  final String catalogChannelTitle;

  final int filesChannelId;

  final String filesChannelTitle;

  final Map<int, int> partMessageIds;

  final int manifestMessageId;

  final int uploadedPartsNow;

  final int reusedParts;

  final bool alreadyUploaded;

  final List<int> galleryMessageIds;

  final int? galleryGroupedId;

  final List<int> fileGroupedIds;

  const TelegramStoragePackageUploadResult({
    required this.packageId,
    required this.catalogChannelId,
    required this.catalogChannelTitle,
    required this.filesChannelId,
    required this.filesChannelTitle,
    required this.partMessageIds,
    required this.manifestMessageId,
    required this.uploadedPartsNow,
    required this.reusedParts,
    required this.alreadyUploaded,
    required this.galleryMessageIds,
    required this.galleryGroupedId,
    required this.fileGroupedIds,
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