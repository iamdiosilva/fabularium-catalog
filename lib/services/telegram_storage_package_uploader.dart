import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../models/telegram_storage_channel.dart';
import '../models/telegram_storage_package.dart';
import 'telegram_storage_media_group_service.dart';
import 'telegram_storage_packager.dart';

typedef TelegramStoragePackageUploadProgressCallback =
    void Function(
  TelegramStoragePackageUploadProgress progress,
);

class TelegramStoragePackageUploader {
  TelegramStoragePackageUploader._();

  static final TelegramStoragePackageUploader instance =
      TelegramStoragePackageUploader._();

  final TelegramStoragePackager _packager =
      TelegramStoragePackager.instance;

  final TelegramStorageMediaGroupService _mediaGroups =
      TelegramStorageMediaGroupService.instance;

  /*
   * 9 partes + manifest = 10 documentos
   * no último grupo.
   */
  static const int _partsPerDocumentGroup =
      9;

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

    await _validateLocalPackage(
      package,
    );

    /*
     * Manifest V2 não depende dos messageIds.
     *
     * Dessa forma ele pode entrar no próprio
     * media group final.
     */
    await _packager.writeManifest(
      package,
      channelId:
          channel.id,
      channelTitle:
          channel.title,
    );

    final plans =
        _createFileGroupPlans(
      package,
    );

    var receipt =
        await _loadReceipt(
      package:
          package,
      channel:
          channel,
    );

    receipt ??=
        _UploadReceiptState(
      packageId:
          package.packageId,
      channelId:
          channel.id,
      channelTitle:
          channel.title,
      gallery:
          null,
      fileGroups:
          <int, _ReceiptFileGroup>{},
      completed:
          false,
    );

    // ==========================================================
    // ALREADY COMPLETE
    // ==========================================================

    if (_isReceiptComplete(
      receipt:
          receipt,
      package:
          package,
      plans:
          plans,
    )) {
      return _buildResult(
        package:
            package,
        channel:
            channel,
        receipt:
            receipt,
        uploadedPartsNow:
            0,
        reusedParts:
            package.partCount,
        alreadyUploaded:
            true,
      );
    }

    int uploadedPartsNow = 0;

    int reusedParts = 0;

    // ==========================================================
    // 1. GALLERY
    // ==========================================================

    final galleryPaths =
        package.galleryImagePaths;

    if (galleryPaths.isNotEmpty) {
      final galleryComplete =
          receipt.gallery != null &&
              receipt
                      .gallery!
                      .messageIds
                      .length ==
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
          final path =
              galleryPaths[index];

          galleryItems.add(
            TelegramStorageMediaItem(
              kind:
                  TelegramStorageMediaKind
                      .photo,
              filePath:
                  path,
              fileName:
                  p.basename(
                path,
              ),
              mimeType:
                  _mimeTypeForImage(
                path,
              ),
              caption:
                  index == 0
                      ? caption
                      : '',
              randomIdKey:
                  '${package.packageId}'
                  ':gallery:$index',
            ),
          );
        }

        final galleryResult =
            await _mediaGroups.sendGroup(
          channel:
              channel,
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
            );
          },
        );

        receipt =
            receipt.copyWith(
          gallery:
              _ReceiptGallery(
            groupedId:
                galleryResult.groupedId,
            messageIds:
                galleryResult.messageIds,
          ),
        );

        await _writeReceipt(
          package:
              package,
          receipt:
              receipt,
        );
      }
    }

    // ==========================================================
    // 2. DOCUMENT GROUPS
    // ==========================================================

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
          receipt.fileGroups[
            plan.groupIndex
          ];

      // ========================================================
      // REUSE COMPLETE GROUP
      // ========================================================

      if (_isFileGroupComplete(
        plan:
            plan,
        receiptGroup:
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

      final items =
          <TelegramStorageMediaItem>[];

      final caption =
          _buildFilesCaption(
        package:
            package,
        groupIndex:
            plan.groupIndex,
        totalGroups:
            plans.length,
        includesManifest:
            plan.includesManifest,
      );

      // ========================================================
      // PARTS
      // ========================================================

      for (int index = 0;
          index < plan.parts.length;
          index++) {
        final part =
            plan.parts[index];

        items.add(
          TelegramStorageMediaItem(
            kind:
                TelegramStorageMediaKind
                    .document,
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
                ':files:${plan.groupIndex}'
                ':part:${part.index}',
          ),
        );
      }

      // ========================================================
      // MANIFEST - ONLY LAST GROUP
      // ========================================================

      if (plan.includesManifest) {
        items.add(
          TelegramStorageMediaItem(
            kind:
                TelegramStorageMediaKind
                    .document,
            filePath:
                package.manifestPath,
            fileName:
                p.basename(
              package.manifestPath,
            ),
            mimeType:
                'application/json',
            caption:
                plan.parts.isEmpty
                    ? caption
                    : '',
            randomIdKey:
                '${package.packageId}'
                ':files:${plan.groupIndex}'
                ':manifest',
          ),
        );
      }

      final bytesBeforeGroup =
          completedFileBytes;

      final groupPartBytes =
          plan.parts.fold<int>(
        0,
        (
          total,
          part,
        ) =>
            total +
            part.size,
      );

      _report(
        onProgress,
        overallProgress:
            _mapFileProgress(
          completedFileBytes,
          totalFileBytes,
        ),
        stage:
            'Uploading files '
            '${plan.groupIndex}/'
            '${plans.length}...',
        currentPart:
            plan.parts.isEmpty
                ? 0
                : plan.parts.first.index,
        totalParts:
            package.partCount,
      );

      // ========================================================
      // SEND MEDIA GROUP
      // ========================================================

      final result =
          await _mediaGroups.sendGroup(
        channel:
            channel,
        items:
            items,
        onProgress:
            (
          progress,
          stage,
        ) {
          final insideBytes =
              groupPartBytes *
                  progress;

          final effective =
              bytesBeforeGroup +
                  insideBytes;

          _report(
            onProgress,
            overallProgress:
                _mapFileProgress(
              effective,
              totalFileBytes,
            ),
            stage:
                stage,
            currentPart:
                plan.parts.isEmpty
                    ? 0
                    : plan.parts.first.index,
            totalParts:
                package.partCount,
          );
        },
      );

      if (result.messageIds.length !=
          items.length) {
        throw const TelegramStoragePackageUploadException(
          'Telegram returned an incomplete '
          'document group.',
        );
      }

      // ========================================================
      // MESSAGE IDS
      // ========================================================

      final partMessageIds =
          <int, int>{};

      for (int index = 0;
          index < plan.parts.length;
          index++) {
        partMessageIds[
            plan.parts[index].index] =
            result.messageIds[index];
      }

      int? manifestMessageId;

      if (plan.includesManifest) {
        manifestMessageId =
            result.messageIds.last;
      }

      receipt.fileGroups[
          plan.groupIndex] =
          _ReceiptFileGroup(
        groupIndex:
            plan.groupIndex,
        groupedId:
            result.groupedId,
        messageIds:
            result.messageIds,
        partMessageIds:
            partMessageIds,
        manifestMessageId:
            manifestMessageId,
      );

      uploadedPartsNow +=
          plan.parts.length;

      completedFileBytes +=
          groupPartBytes;

      /*
       * Persistimos depois de cada media group.
       */
      await _writeReceipt(
        package:
            package,
        receipt:
            receipt,
      );
    }

    // ==========================================================
    // COMPLETE
    // ==========================================================

    receipt =
        receipt.copyWith(
      completed:
          true,
    );

    await _writeReceipt(
      package:
          package,
      receipt:
          receipt,
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
    );

    return _buildResult(
      package:
          package,
      channel:
          channel,
      receipt:
          receipt,
      uploadedPartsNow:
          uploadedPartsNow,
      reusedParts:
          reusedParts,
      alreadyUploaded:
          false,
    );
  }

  // ============================================================
  // GROUP PLANS
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

    final groups =
        <_FileGroupPlan>[];

    int offset = 0;

    int groupIndex = 1;

    while (offset <
        sorted.length) {
      final int remaining =
          sorted.length -
              offset;

      final int count =
          min<int>(
        _partsPerDocumentGroup,
        remaining,
      );

      final parts =
          sorted.sublist(
        offset,
        offset +
            count,
      );

      final bool isLast =
          offset +
                  count >=
              sorted.length;

      groups.add(
        _FileGroupPlan(
          groupIndex:
              groupIndex,
          parts:
              parts,
          includesManifest:
              isLast,
        ),
      );

      offset +=
          count;

      groupIndex++;
    }

    return groups;
  }

  // ============================================================
  // GALLERY CAPTION
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
      'Archive: '
      '${_formatBytes(package.archiveSize)}',
    );

    buffer.writeln(
      'Parts: '
      '${package.partCount}',
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

    return result.length >
            900
        ? result.substring(
            0,
            900,
          )
        : result;
  }

  // ============================================================
  // FILE CAPTION
  // ============================================================

  String _buildFilesCaption({
    required TelegramStoragePackage package,
    required int groupIndex,
    required int totalGroups,
    required bool includesManifest,
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
        'Files '
        '$groupIndex/$totalGroups',
      );
    } else {
      buffer.writeln(
        'Storage Files',
      );
    }

    if (includesManifest) {
      buffer.writeln(
        'Includes package manifest',
      );
    }

    return buffer
        .toString()
        .trim();
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
  // VALIDATE PACKAGE
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
        'The package staging folder '
        'no longer exists.',
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
          'Missing storage part: '
          '${part.fileName}',
        );
      }

      final length =
          await file.length();

      if (length !=
          part.size) {
        throw TelegramStoragePackageUploadException(
          'Storage part size changed: '
          '${part.fileName}',
        );
      }
    }

    for (final imagePath
        in package.galleryImagePaths) {
      final image =
          File(
        imagePath,
      );

      if (!await image.exists()) {
        throw TelegramStoragePackageUploadException(
          'Gallery image no longer exists: '
          '${p.basename(imagePath)}',
        );
      }
    }
  }

  // ============================================================
  // RECEIPT PATH
  // ============================================================

  String _receiptPath(
    TelegramStoragePackage package,
  ) {
    return p.join(
      package.stagingDirectoryPath,
      '${package.packageId}.upload.json',
    );
  }

  // ============================================================
  // LOAD RECEIPT
  // ============================================================

  Future<_UploadReceiptState?>
      _loadReceipt({
    required TelegramStoragePackage package,
    required TelegramStorageChannel channel,
  }) async {
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

      /*
       * Receipts da versão antiga não são
       * reutilizados no formato media group.
       */
      if (root['version'] != 2 ||
          root['packageId'] !=
              package.packageId) {
        return null;
      }

      final channelData =
          root['channel'];

      if (channelData is! Map) {
        return null;
      }

      final channelMap =
          Map<String, dynamic>.from(
        channelData,
      );

      final storedChannelId =
          _readInt(
        channelMap['id'],
      );

      if (storedChannelId !=
          channel.id) {
        return null;
      }

      // ========================================================
      // GALLERY
      // ========================================================

      _ReceiptGallery? gallery;

      final rawGallery =
          root['gallery'];

      if (rawGallery is Map) {
        final map =
            Map<String, dynamic>.from(
          rawGallery,
        );

        gallery =
            _ReceiptGallery(
          groupedId:
              _readInt(
            map['groupedId'],
          ),
          messageIds:
              _readIntList(
            map['messageIds'],
          ),
        );
      }

      // ========================================================
      // FILE GROUPS
      // ========================================================

      final fileGroups =
          <int, _ReceiptFileGroup>{};

      final rawGroups =
          root['fileGroups'];

      if (rawGroups is List) {
        for (final dynamic rawGroup
            in rawGroups) {
          if (rawGroup is! Map) {
            continue;
          }

          final map =
              Map<String, dynamic>.from(
            rawGroup,
          );

          final groupIndex =
              _readInt(
            map['groupIndex'],
          );

          if (groupIndex == null) {
            continue;
          }

          final partMessageIds =
              <int, int>{};

          final rawPartIds =
              map['partMessageIds'];

          if (rawPartIds is Map) {
            for (final entry
                in rawPartIds.entries) {
              final partIndex =
                  int.tryParse(
                entry.key
                    .toString(),
              );

              final messageId =
                  _readInt(
                entry.value,
              );

              if (partIndex != null &&
                  messageId != null) {
                partMessageIds[
                    partIndex] =
                    messageId;
              }
            }
          }

          fileGroups[
              groupIndex] =
              _ReceiptFileGroup(
            groupIndex:
                groupIndex,
            groupedId:
                _readInt(
              map['groupedId'],
            ),
            messageIds:
                _readIntList(
              map['messageIds'],
            ),
            partMessageIds:
                partMessageIds,
            manifestMessageId:
                _readInt(
              map['manifestMessageId'],
            ),
          );
        }
      }

      return _UploadReceiptState(
        packageId:
            package.packageId,
        channelId:
            channel.id,
        channelTitle:
            channel.title,
        gallery:
            gallery,
        fileGroups:
            fileGroups,
        completed:
            root['completed'] ==
                true,
      );
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // WRITE RECEIPT
  // ============================================================

  Future<void> _writeReceipt({
    required TelegramStoragePackage package,
    required _UploadReceiptState receipt,
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

    final groups =
        receipt.fileGroups.values
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

    final encoder =
        const JsonEncoder.withIndent(
      '  ',
    );

    await temp.writeAsString(
      encoder.convert(
        <String, dynamic>{
          'version':
              2,
          'kind':
              'fabularium-storage-upload-receipt',
          'packageId':
              receipt.packageId,
          'updatedAt':
              DateTime.now()
                  .toUtc()
                  .toIso8601String(),
          'completed':
              receipt.completed,

          'channel':
              <String, dynamic>{
            'id':
                receipt.channelId,
            'title':
                receipt.channelTitle,
          },

          'gallery':
              receipt.gallery ==
                      null
                  ? null
                  : <String, dynamic>{
                      'groupedId':
                          receipt
                              .gallery!
                              .groupedId,
                      'messageIds':
                          receipt
                              .gallery!
                              .messageIds,
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
                      'partMessageIds':
                          group
                              .partMessageIds
                              .map(
                        (
                          key,
                          value,
                        ) =>
                            MapEntry<
                                String,
                                int>(
                          key.toString(),
                          value,
                        ),
                      ),
                      'manifestMessageId':
                          group
                              .manifestMessageId,
                    },
                  )
                  .toList(),
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
  }

  // ============================================================
  // GROUP COMPLETE?
  // ============================================================

  bool _isFileGroupComplete({
    required _FileGroupPlan plan,
    required _ReceiptFileGroup?
        receiptGroup,
  }) {
    if (receiptGroup == null) {
      return false;
    }

    final int expected =
        plan.parts.length +
            (plan.includesManifest
                ? 1
                : 0);

    if (receiptGroup.messageIds.length !=
        expected) {
      return false;
    }

    for (final id
        in receiptGroup.messageIds) {
      if (id <= 0) {
        return false;
      }
    }

    for (final part
        in plan.parts) {
      if (!receiptGroup
          .partMessageIds
          .containsKey(
        part.index,
      )) {
        return false;
      }
    }

    if (plan.includesManifest &&
        receiptGroup.manifestMessageId ==
            null) {
      return false;
    }

    return true;
  }

  // ============================================================
  // RECEIPT COMPLETE?
  // ============================================================

  bool _isReceiptComplete({
    required _UploadReceiptState receipt,
    required TelegramStoragePackage package,
    required List<_FileGroupPlan> plans,
  }) {
    if (!receipt.completed) {
      return false;
    }

    if (package.galleryImagePaths.isNotEmpty) {
      if (receipt.gallery == null ||
          receipt
                  .gallery!
                  .messageIds
                  .length !=
              package
                  .galleryImagePaths
                  .length) {
        return false;
      }
    }

    for (final plan
        in plans) {
      if (!_isFileGroupComplete(
        plan:
            plan,
        receiptGroup:
            receipt.fileGroups[
              plan.groupIndex
            ],
      )) {
        return false;
      }
    }

    return true;
  }

  // ============================================================
  // BUILD PUBLIC RESULT
  // ============================================================

  TelegramStoragePackageUploadResult
      _buildResult({
    required TelegramStoragePackage package,
    required TelegramStorageChannel channel,
    required _UploadReceiptState receipt,
    required int uploadedPartsNow,
    required int reusedParts,
    required bool alreadyUploaded,
  }) {
    final partMessageIds =
        <int, int>{};

    int? manifestMessageId;

    final fileGroupedIds =
        <int>[];

    final groups =
        receipt.fileGroups.values
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

      manifestMessageId ??=
          group.manifestMessageId;

      if (group.groupedId !=
          null) {
        fileGroupedIds.add(
          group.groupedId!,
        );
      }
    }

    if (manifestMessageId ==
        null) {
      throw const TelegramStoragePackageUploadException(
        'Storage upload completed '
        'without a manifest message ID.',
      );
    }

    return TelegramStoragePackageUploadResult(
      packageId:
          package.packageId,
      channelId:
          channel.id,
      channelTitle:
          channel.title,
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
      receiptPath:
          _receiptPath(
        package,
      ),
      galleryMessageIds:
          receipt.gallery
                  ?.messageIds ??
              const <int>[],
      galleryGroupedId:
          receipt.gallery
              ?.groupedId,
      fileGroupedIds:
          fileGroupedIds,
    );
  }

  // ============================================================
  // PROGRESS
  // ============================================================

  double _mapFileProgress(
    num bytes,
    int totalBytes,
  ) {
    if (totalBytes <= 0) {
      return 0.10;
    }

    /*
     * 0 - 10%:
     * gallery
     *
     * 10 - 100%:
     * package documents
     */
    return 0.10 +
        ((bytes /
                    totalBytes)
                .clamp(
                  0.0,
                  1.0,
                ) *
            0.90);
  }

  void _report(
    TelegramStoragePackageUploadProgressCallback?
        callback, {
    required double overallProgress,
    required String stage,
    required int currentPart,
    required int totalParts,
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
            null,
        currentFileProgress:
            overallProgress
                .clamp(
                  0.0,
                  1.0,
                )
                .toDouble(),
      ),
    );
  }

  // ============================================================
  // JSON HELPERS
  // ============================================================

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

  List<int> _readIntList(
    dynamic value,
  ) {
    if (value is! List) {
      return <int>[];
    }

    return value
        .map(
          _readInt,
        )
        .whereType<int>()
        .toList();
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
// FILE GROUP PLAN
// ============================================================

class _FileGroupPlan {
  final int groupIndex;

  final List<TelegramStoragePackagePart> parts;

  final bool includesManifest;

  const _FileGroupPlan({
    required this.groupIndex,
    required this.parts,
    required this.includesManifest,
  });
}

// ============================================================
// RECEIPT STATE
// ============================================================

class _UploadReceiptState {
  final String packageId;

  final int channelId;

  final String channelTitle;

  final _ReceiptGallery? gallery;

  final Map<int, _ReceiptFileGroup>
      fileGroups;

  final bool completed;

  const _UploadReceiptState({
    required this.packageId,
    required this.channelId,
    required this.channelTitle,
    required this.gallery,
    required this.fileGroups,
    required this.completed,
  });

  _UploadReceiptState copyWith({
    _ReceiptGallery? gallery,
    bool? completed,
  }) {
    return _UploadReceiptState(
      packageId:
          packageId,
      channelId:
          channelId,
      channelTitle:
          channelTitle,
      gallery:
          gallery ??
          this.gallery,
      fileGroups:
          fileGroups,
      completed:
          completed ??
          this.completed,
    );
  }
}

class _ReceiptGallery {
  final int? groupedId;

  final List<int> messageIds;

  const _ReceiptGallery({
    required this.groupedId,
    required this.messageIds,
  });
}

class _ReceiptFileGroup {
  final int groupIndex;

  final int? groupedId;

  final List<int> messageIds;

  final Map<int, int>
      partMessageIds;

  final int? manifestMessageId;

  const _ReceiptFileGroup({
    required this.groupIndex,
    required this.groupedId,
    required this.messageIds,
    required this.partMessageIds,
    required this.manifestMessageId,
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

  final int channelId;

  final String channelTitle;

  final Map<int, int>
      partMessageIds;

  final int manifestMessageId;

  final int uploadedPartsNow;

  final int reusedParts;

  final bool alreadyUploaded;

  final String receiptPath;

  final List<int>
      galleryMessageIds;

  final int? galleryGroupedId;

  final List<int> fileGroupedIds;

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
    this.galleryMessageIds =
        const <int>[],
    this.galleryGroupedId,
    this.fileGroupedIds =
        const <int>[],
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