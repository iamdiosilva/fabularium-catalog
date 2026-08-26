import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../models/telegram_storage_package.dart';
import '../models/telegram_storage_upload_journal.dart';
import '../models/telegram_storage_workspace.dart';
import 'telegram_storage_media_group_service.dart';
import 'telegram_storage_upload_journal_service.dart';

typedef TelegramStoragePackageUploadProgressCallback = void Function(
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

  static const int _partsPerDocumentGroup = 10;

  Future<TelegramStoragePackageUploadResult> uploadPackage({
    required TelegramStorageWorkspace workspace,
    required TelegramStoragePackage package,
    TelegramStoragePackageUploadProgressCallback? onProgress,
  }) async {
    final catalogChannel = workspace.catalogChannel;
    final filesChannel = workspace.filesChannel;

    if (catalogChannel == null || filesChannel == null) {
      throw const TelegramStoragePackageUploadException(
        'Configure both Catalog Channel and Files Channel before uploading a package.',
      );
    }

    if (catalogChannel.id == filesChannel.id) {
      throw const TelegramStoragePackageUploadException(
        'Catalog Channel and Files Channel must be different.',
      );
    }

    if (package.parts.isEmpty) {
      throw const TelegramStoragePackageUploadException(
        'The prepared package contains no files.',
      );
    }

    final plans = _createFileGroupPlans(package);

    final existingJournal = await _journalService.load(package.packageId);

    if (existingJournal != null &&
        (existingJournal.catalogChannel.id != catalogChannel.id ||
            existingJournal.filesChannel.id != filesChannel.id)) {
      throw const TelegramStoragePackageUploadException(
        'This package already has an upload journal linked to different Telegram channels.',
      );
    }

    var journal = existingJournal ??
        TelegramStorageUploadJournal(
          packageId: package.packageId,
          modelName: package.displayName,
          stagingDirectoryPath: package.stagingDirectoryPath,
          catalogChannel: catalogChannel,
          filesChannel: filesChannel,
          status: TelegramStorageUploadStatus.preparing,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          galleryGroupedId: null,
          galleryMessageIds: const <int>[],
          fileGroups: <int, TelegramStorageUploadJournalGroup>{},
          manifestMessageId: null,
          lastError: null,
        );

    await _journalService.save(journal);

    if (_isJournalComplete(
      journal: journal,
      package: package,
      plans: plans,
    )) {
      return _buildResult(
        package: package,
        journal: journal,
        uploadedPartsNow: 0,
        reusedParts: package.partCount,
        alreadyUploaded: true,
      );
    }

    // Recovery/Repair may leave already completed Telegram groups whose local
    // files no longer exist. Validate only the files that Resume really needs
    // to upload again.
    await _validateRequiredLocalFiles(
      package: package,
      journal: journal,
      plans: plans,
    );

    journal = await _journalService.markUploading(journal);

    var uploadedPartsNow = 0;
    var reusedParts = 0;

    try {
      // ========================================================
      // 1. CATALOG GALLERY
      // ========================================================

      final galleryPaths = package.galleryImagePaths;
      final galleryComplete = galleryPaths.isEmpty ||
          journal.galleryMessageIds.length == galleryPaths.length;

      if (!galleryComplete) {
        _report(
          onProgress,
          overallProgress: 0,
          stage: 'Uploading catalog gallery...',
          currentPart: 0,
          totalParts: package.partCount,
          currentFileName: null,
          currentFileProgress: 0,
        );

        final caption = _buildGalleryCaption(package);
        final items = <TelegramStorageMediaItem>[];

        for (var index = 0; index < galleryPaths.length; index++) {
          final imagePath = galleryPaths[index];

          items.add(
            TelegramStorageMediaItem(
              kind: TelegramStorageMediaKind.photo,
              filePath: imagePath,
              fileName: p.basename(imagePath),
              mimeType: _mimeTypeForImage(imagePath),
              caption: index == 0 ? caption : '',
              randomIdKey:
                  '${package.packageId}:catalog:gallery:$index',
            ),
          );
        }

        final galleryResult = await _mediaGroups.sendGroup(
          channel: catalogChannel,
          items: items,
          onProgress: (progress, stage) {
            _report(
              onProgress,
              overallProgress: progress * 0.10,
              stage: stage,
              currentPart: 0,
              totalParts: package.partCount,
              currentFileName: null,
              currentFileProgress: progress,
            );
          },
        );

        journal = journal.copyWith(
          galleryGroupedId: galleryResult.groupedId,
          galleryMessageIds: galleryResult.messageIds,
        );

        await _journalService.save(journal);
      }

      // ========================================================
      // 2. FILE GROUPS
      // ========================================================

      final totalFileBytes = package.parts.fold<int>(
        0,
        (total, part) => total + part.size,
      );

      var completedFileBytes = 0;

      for (final plan in plans) {
        final existing = journal.fileGroups[plan.groupIndex];

        if (_isFileGroupComplete(
          plan: plan,
          journalGroup: existing,
        )) {
          reusedParts += plan.parts.length;
          completedFileBytes += plan.parts.fold<int>(
            0,
            (total, part) => total + part.size,
          );
          continue;
        }

        final groupBytes = plan.parts.fold<int>(
          0,
          (total, part) => total + part.size,
        );
        final bytesBeforeGroup = completedFileBytes;
        final caption = _buildFilesCaption(
          package: package,
          groupIndex: plan.groupIndex,
          totalGroups: plans.length,
        );

        final items = <TelegramStorageMediaItem>[];

        for (var index = 0; index < plan.parts.length; index++) {
          final part = plan.parts[index];

          items.add(
            TelegramStorageMediaItem(
              kind: TelegramStorageMediaKind.document,
              filePath: part.filePath,
              fileName: part.fileName,
              mimeType: 'application/octet-stream',
              caption: index == 0 ? caption : '',
              randomIdKey: '${package.packageId}'
                  ':storage:group:${plan.groupIndex}'
                  ':part:${part.index}',
            ),
          );
        }

        _report(
          onProgress,
          overallProgress: _mapFilesProgress(
            completedFileBytes,
            totalFileBytes,
          ),
          stage: 'Uploading files ${plan.groupIndex}/${plans.length}...',
          currentPart: plan.parts.first.index,
          totalParts: package.partCount,
          currentFileName: plan.parts.first.fileName,
          currentFileProgress: 0,
        );

        final result = await _mediaGroups.sendGroup(
          channel: filesChannel,
          items: items,
          onProgress: (progress, stage) {
            final estimatedBytes =
                bytesBeforeGroup + (groupBytes * progress);

            _report(
              onProgress,
              overallProgress: _mapFilesProgress(
                estimatedBytes,
                totalFileBytes,
              ),
              stage: stage,
              currentPart: plan.parts.first.index,
              totalParts: package.partCount,
              currentFileName: plan.parts.first.fileName,
              currentFileProgress: progress,
            );
          },
        );

        if (result.messageIds.length != plan.parts.length) {
          throw const TelegramStoragePackageUploadException(
            'Telegram returned an incomplete file group.',
          );
        }

        final partMessageIds = <int, int>{};

        for (var index = 0; index < plan.parts.length; index++) {
          partMessageIds[plan.parts[index].index] = result.messageIds[index];
        }

        final updatedGroups =
            Map<int, TelegramStorageUploadJournalGroup>.from(
          journal.fileGroups,
        );

        updatedGroups[plan.groupIndex] = TelegramStorageUploadJournalGroup(
          groupIndex: plan.groupIndex,
          groupedId: result.groupedId,
          messageIds: result.messageIds,
          partMessageIds: partMessageIds,
        );

        journal = journal.copyWith(
          fileGroups: updatedGroups,
        );

        await _journalService.save(journal);

        uploadedPartsNow += plan.parts.length;
        completedFileBytes += groupBytes;
      }

      // ========================================================
      // 3. FINAL MANIFEST V3
      // ========================================================

      if (!journal.hasManifest) {
        _report(
          onProgress,
          overallProgress: 0.95,
          stage: 'Creating final manifest...',
          currentPart: package.partCount,
          totalParts: package.partCount,
          currentFileName: p.basename(package.manifestPath),
          currentFileProgress: 0,
        );

        await _writeManifestV3(
          package: package,
          journal: journal,
        );

        final manifestItem = TelegramStorageMediaItem(
          kind: TelegramStorageMediaKind.document,
          filePath: package.manifestPath,
          fileName: p.basename(package.manifestPath),
          mimeType: 'application/json',
          caption: _buildManifestCaption(package),
          randomIdKey: '${package.packageId}:storage:manifest:v3',
        );

        final manifestResult = await _mediaGroups.sendGroup(
          channel: filesChannel,
          items: <TelegramStorageMediaItem>[manifestItem],
          onProgress: (progress, stage) {
            _report(
              onProgress,
              overallProgress: 0.95 + (progress * 0.05),
              stage: stage,
              currentPart: package.partCount,
              totalParts: package.partCount,
              currentFileName: p.basename(package.manifestPath),
              currentFileProgress: progress,
            );
          },
        );

        if (manifestResult.messageIds.length != 1) {
          throw const TelegramStoragePackageUploadException(
            'Telegram did not return the manifest message ID.',
          );
        }

        journal = journal.copyWith(
          manifestMessageId: manifestResult.messageIds.single,
        );

        await _journalService.save(journal);
      }

      // ========================================================
      // 4. STORED
      // ========================================================

      journal = await _journalService.markStored(journal);

      _report(
        onProgress,
        overallProgress: 1,
        stage: 'Package stored successfully.',
        currentPart: package.partCount,
        totalParts: package.partCount,
        currentFileName: null,
        currentFileProgress: 1,
      );

      return _buildResult(
        package: package,
        journal: journal,
        uploadedPartsNow: uploadedPartsNow,
        reusedParts: reusedParts,
        alreadyUploaded: false,
      );
    } catch (error) {
      try {
        journal = await _journalService.markFailed(journal, error);
      } catch (_) {}

      rethrow;
    }
  }

  // ============================================================
  // SELECTIVE LOCAL VALIDATION
  // ============================================================

  Future<void> _validateRequiredLocalFiles({
    required TelegramStoragePackage package,
    required TelegramStorageUploadJournal journal,
    required List<_FileGroupPlan> plans,
  }) async {
    final staging = Directory(package.stagingDirectoryPath);

    if (!await staging.exists()) {
      throw const TelegramStoragePackageUploadException(
        'The package staging folder no longer exists.',
      );
    }

    final galleryComplete = package.galleryImagePaths.isEmpty ||
        journal.galleryMessageIds.length == package.galleryImagePaths.length;

    if (!galleryComplete) {
      for (final imagePath in package.galleryImagePaths) {
        if (!await File(imagePath).exists()) {
          throw TelegramStoragePackageUploadException(
            'Gallery image required by Resume no longer exists: '
            '${p.basename(imagePath)}',
          );
        }
      }
    }

    for (final plan in plans) {
      if (_isFileGroupComplete(
        plan: plan,
        journalGroup: journal.fileGroups[plan.groupIndex],
      )) {
        continue;
      }

      for (final part in plan.parts) {
        final file = File(part.filePath);

        if (!await file.exists()) {
          throw TelegramStoragePackageUploadException(
            'Storage part required by Resume is missing: ${part.fileName}',
          );
        }

        final length = await file.length();

        if (length != part.size) {
          throw TelegramStoragePackageUploadException(
            'Storage part required by Resume changed size: ${part.fileName}',
          );
        }
      }
    }
  }

  List<_FileGroupPlan> _createFileGroupPlans(
    TelegramStoragePackage package,
  ) {
    final sorted = List<TelegramStoragePackagePart>.from(package.parts)
      ..sort((a, b) => a.index.compareTo(b.index));

    final result = <_FileGroupPlan>[];
    var offset = 0;
    var groupIndex = 1;

    while (offset < sorted.length) {
      final remaining = sorted.length - offset;
      final count = min<int>(_partsPerDocumentGroup, remaining);

      result.add(
        _FileGroupPlan(
          groupIndex: groupIndex,
          parts: sorted.sublist(offset, offset + count),
        ),
      );

      offset += count;
      groupIndex++;
    }

    return result;
  }

  bool _isFileGroupComplete({
    required _FileGroupPlan plan,
    required TelegramStorageUploadJournalGroup? journalGroup,
  }) {
    if (journalGroup == null ||
        journalGroup.messageIds.length != plan.parts.length) {
      return false;
    }

    for (final messageId in journalGroup.messageIds) {
      if (messageId <= 0) {
        return false;
      }
    }

    for (final part in plan.parts) {
      final messageId = journalGroup.partMessageIds[part.index];

      if (messageId == null || messageId <= 0) {
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
    if (!journal.isStored || !journal.hasManifest) {
      return false;
    }

    if (package.galleryImagePaths.isNotEmpty &&
        journal.galleryMessageIds.length != package.galleryImagePaths.length) {
      return false;
    }

    for (final plan in plans) {
      if (!_isFileGroupComplete(
        plan: plan,
        journalGroup: journal.fileGroups[plan.groupIndex],
      )) {
        return false;
      }
    }

    return true;
  }

  Future<void> _writeManifestV3({
    required TelegramStoragePackage package,
    required TelegramStorageUploadJournal journal,
  }) async {
    final partMessageIds = <int, int>{};
    final groups = journal.fileGroups.values.toList()
      ..sort((a, b) => a.groupIndex.compareTo(b.groupIndex));

    for (final group in groups) {
      partMessageIds.addAll(group.partMessageIds);
    }

    final root = <String, dynamic>{
      'version': 3,
      'kind': 'fabularium-storage-package',
      'packageId': package.packageId,
      'createdAt': package.createdAt.toUtc().toIso8601String(),
      'catalog': package.catalog?.toManifestJson() ??
          <String, dynamic>{'name': package.sourceFolderName},
      'source': <String, dynamic>{
        'folderName': package.sourceFolderName,
        'size': package.sourceSize,
      },
      'archive': <String, dynamic>{
        'fileName': package.archiveFileName,
        'size': package.archiveSize,
        'sha256': package.archiveSha256,
        'split': package.isSplit,
        'partCount': package.partCount,
      },
      'telegram': <String, dynamic>{
        'catalogChannel': <String, dynamic>{
          'id': journal.catalogChannel.id,
          'title': journal.catalogChannel.title,
        },
        'filesChannel': <String, dynamic>{
          'id': journal.filesChannel.id,
          'title': journal.filesChannel.title,
        },
        'gallery': <String, dynamic>{
          'groupedId': journal.galleryGroupedId,
          'messageIds': journal.galleryMessageIds,
        },
        'fileGroups': groups
            .map(
              (group) => <String, dynamic>{
                'groupIndex': group.groupIndex,
                'groupedId': group.groupedId,
                'messageIds': group.messageIds,
              },
            )
            .toList(),
      },
      'parts': package.parts
          .map(
            (part) => <String, dynamic>{
              ...part.toManifestJson(),
              'messageId': partMessageIds[part.index],
            },
          )
          .toList(),
    };

    final file = File(package.manifestPath);
    await file.parent.create(recursive: true);

    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(root),
      flush: true,
    );

    if (await file.exists()) {
      await file.delete();
    }

    await temp.rename(file.path);
  }

  String _buildGalleryCaption(TelegramStoragePackage package) {
    final catalog = package.catalog;
    final buffer = StringBuffer()
      ..writeln('[FABULARIUM:${package.packageId}]')
      ..writeln()
      ..writeln('🖼 ${package.displayName}');

    if (catalog?.studio != null) {
      buffer.writeln('Studio: ${catalog!.studio}');
    }
    if (catalog?.category != null) {
      buffer.writeln('Category: ${catalog!.category}');
    }
    if (catalog?.type != null) {
      buffer.writeln('Type: ${catalog!.type}');
    }
    if (catalog?.scale != null) {
      buffer.writeln('Scale: ${catalog!.scale}');
    }
    if (catalog?.height != null) {
      buffer.writeln('Height: ${catalog!.height}');
    }

    buffer
      ..writeln()
      ..writeln('Archive: ${_formatBytes(package.archiveSize)}')
      ..writeln('Parts: ${package.partCount}');

    final description = catalog?.description?.trim();

    if (description != null && description.isNotEmpty) {
      buffer.writeln();
      buffer.write(
        description.length > 350
            ? '${description.substring(0, 347)}...'
            : description,
      );
    }

    final result = buffer.toString().trim();
    return result.length <= 900 ? result : result.substring(0, 900);
  }

  String _buildFilesCaption({
    required TelegramStoragePackage package,
    required int groupIndex,
    required int totalGroups,
  }) {
    final label = totalGroups > 1
        ? 'Files $groupIndex/$totalGroups'
        : 'Storage Files';

    return '[FABULARIUM:${package.packageId}]\n\n'
        '📦 ${package.displayName}\n'
        '$label';
  }

  String _buildManifestCaption(TelegramStoragePackage package) {
    return '[FABULARIUM_MANIFEST:${package.packageId}]\n\n'
        '📋 ${package.displayName}\n'
        'Storage Manifest V3';
  }

  String _mimeTypeForImage(String path) {
    return p.extension(path).toLowerCase() == '.png'
        ? 'image/png'
        : 'image/jpeg';
  }

  double _mapFilesProgress(num bytes, int totalBytes) {
    if (totalBytes <= 0) {
      return 0.10;
    }

    return 0.10 + (bytes / totalBytes).clamp(0.0, 1.0) * 0.85;
  }

  void _report(
    TelegramStoragePackageUploadProgressCallback? callback, {
    required double overallProgress,
    required String stage,
    required int currentPart,
    required int totalParts,
    required String? currentFileName,
    required double currentFileProgress,
  }) {
    callback?.call(
      TelegramStoragePackageUploadProgress(
        overallProgress: overallProgress.clamp(0.0, 1.0).toDouble(),
        stage: stage,
        currentPart: currentPart,
        totalParts: totalParts,
        currentFileName: currentFileName,
        currentFileProgress: currentFileProgress.clamp(0.0, 1.0).toDouble(),
      ),
    );
  }

  TelegramStoragePackageUploadResult _buildResult({
    required TelegramStoragePackage package,
    required TelegramStorageUploadJournal journal,
    required int uploadedPartsNow,
    required int reusedParts,
    required bool alreadyUploaded,
  }) {
    final partMessageIds = <int, int>{};
    final fileGroupedIds = <int>[];
    final groups = journal.fileGroups.values.toList()
      ..sort((a, b) => a.groupIndex.compareTo(b.groupIndex));

    for (final group in groups) {
      partMessageIds.addAll(group.partMessageIds);

      if (group.groupedId != null) {
        fileGroupedIds.add(group.groupedId!);
      }
    }

    final manifestMessageId = journal.manifestMessageId;

    if (manifestMessageId == null) {
      throw const TelegramStoragePackageUploadException(
        'Storage upload completed without a manifest message ID.',
      );
    }

    return TelegramStoragePackageUploadResult(
      packageId: package.packageId,
      catalogChannelId: journal.catalogChannel.id,
      catalogChannelTitle: journal.catalogChannel.title,
      filesChannelId: journal.filesChannel.id,
      filesChannelTitle: journal.filesChannel.title,
      partMessageIds: partMessageIds,
      manifestMessageId: manifestMessageId,
      uploadedPartsNow: uploadedPartsNow,
      reusedParts: reusedParts,
      alreadyUploaded: alreadyUploaded,
      galleryMessageIds: journal.galleryMessageIds,
      galleryGroupedId: journal.galleryGroupedId,
      fileGroupedIds: fileGroupedIds,
    );
  }

  String _formatBytes(int bytes) {
    const mb = 1024 * 1024;
    const gb = mb * 1024;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }

    return '${(bytes / mb).toStringAsFixed(2)} MB';
  }
}

class _FileGroupPlan {
  final int groupIndex;
  final List<TelegramStoragePackagePart> parts;

  const _FileGroupPlan({
    required this.groupIndex,
    required this.parts,
  });
}

class TelegramStoragePackageUploadProgress {
  final double overallProgress;
  final double currentFileProgress;
  final String stage;
  final int currentPart;
  final int totalParts;
  final String? currentFileName;

  const TelegramStoragePackageUploadProgress({
    required this.overallProgress,
    required this.stage,
    required this.currentPart,
    required this.totalParts,
    required this.currentFileName,
    required this.currentFileProgress,
  });
}

class TelegramStoragePackageUploadResult {
  final String packageId;
  final String catalogChannelTitle;
  final String filesChannelTitle;
  final int catalogChannelId;
  final int filesChannelId;
  final int manifestMessageId;
  final int uploadedPartsNow;
  final int reusedParts;
  final Map<int, int> partMessageIds;
  final bool alreadyUploaded;
  final List<int> galleryMessageIds;
  final List<int> fileGroupedIds;
  final int? galleryGroupedId;

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

class TelegramStoragePackageUploadException implements Exception {
  final String message;

  const TelegramStoragePackageUploadException(this.message);

  @override
  String toString() => message;
}
