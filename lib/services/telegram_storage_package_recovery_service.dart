import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/telegram_storage_package.dart';
import '../models/telegram_storage_upload_journal.dart';

class TelegramStoragePackageRecoveryService {
  TelegramStoragePackageRecoveryService._();

  static final TelegramStoragePackageRecoveryService instance =
      TelegramStoragePackageRecoveryService._();

  static const String _fileName =
      'package_recovery.json';

  static const int _version =
      1;

  static const String _kind =
      'fabularium-storage-package-recovery';

  // ============================================================
  // DESCRIPTOR
  // ============================================================

  File _descriptorFile(
    String stagingDirectoryPath,
  ) {
    return File(
      p.join(
        stagingDirectoryPath,
        _fileName,
      ),
    );
  }

  bool hasRecoveryDescriptor(
    TelegramStorageUploadJournal journal,
  ) {
    if (journal.stagingDirectoryPath.trim().isEmpty) {
      return false;
    }

    try {
      return Directory(
            journal.stagingDirectoryPath,
          ).existsSync() &&
          _descriptorFile(
            journal.stagingDirectoryPath,
          ).existsSync();
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // SAVE
  // ============================================================

  Future<void> savePackage(
    TelegramStoragePackage package,
  ) async {
    final directory =
        Directory(
      package.stagingDirectoryPath,
    );

    await directory.create(
      recursive: true,
    );

    final file =
        _descriptorFile(
      package.stagingDirectoryPath,
    );

    final temp =
        File(
      '${file.path}.tmp',
    );

    final catalog =
        package.catalog;

    final encoder =
        const JsonEncoder.withIndent(
      '  ',
    );

    await temp.writeAsString(
      encoder.convert(
        <String, dynamic>{
          'version': _version,
          'kind': _kind,
          'package': <String, dynamic>{
            'packageId':
                package.packageId,
            'sourceFolderName':
                package.sourceFolderName,
            'sourceFolderPath':
                package.sourceFolderPath,
            'sourceSize':
                package.sourceSize,
            'archiveFileName':
                package.archiveFileName,
            'archiveSize':
                package.archiveSize,
            'archiveSha256':
                package.archiveSha256,
            'stagingDirectoryPath':
                package.stagingDirectoryPath,
            'manifestPath':
                package.manifestPath,
            'createdAt':
                package.createdAt
                    .toUtc()
                    .toIso8601String(),
            'parts':
                package.parts
                    .map(
                      (
                        part,
                      ) =>
                          <String, dynamic>{
                        'index':
                            part.index,
                        'filePath':
                            part.filePath,
                        'fileName':
                            part.fileName,
                        'size':
                            part.size,
                        'sha256':
                            part.sha256,
                      },
                    )
                    .toList(),
            'catalog':
                catalog == null
                    ? null
                    : <String, dynamic>{
                        'modelId':
                            catalog.modelId,
                        'name':
                            catalog.name,
                        'studio':
                            catalog.studio,
                        'category':
                            catalog.category,
                        'type':
                            catalog.type,
                        'scale':
                            catalog.scale,
                        'height':
                            catalog.height,
                        'description':
                            catalog.description,
                        'tags':
                            catalog.tags,
                        'galleryImagePaths':
                            catalog.galleryImagePaths,
                      },
          },
        },
      ),
      flush: true,
    );

    if (await file.exists()) {
      await file.delete();
    }

    await temp.rename(
      file.path,
    );
  }

  // ============================================================
  // LOAD FOR JOURNAL
  // ============================================================

  Future<TelegramStoragePackage> loadForJournal(
    TelegramStorageUploadJournal journal,
  ) async {
    final stagingPath =
        journal.stagingDirectoryPath.trim();

    if (stagingPath.isEmpty) {
      throw const TelegramStoragePackageRecoveryException(
        'This journal does not contain a staging directory.',
      );
    }

    final directory =
        Directory(
      stagingPath,
    );

    if (!await directory.exists()) {
      throw const TelegramStoragePackageRecoveryException(
        'The local staging directory no longer exists.',
      );
    }

    final file =
        _descriptorFile(
      stagingPath,
    );

    if (!await file.exists()) {
      throw const TelegramStoragePackageRecoveryException(
        'This upload was created before package recovery support. '
        'Its recovery descriptor is not available.',
      );
    }

    dynamic decoded;

    try {
      decoded =
          jsonDecode(
        await file.readAsString(),
      );
    } catch (e) {
      throw TelegramStoragePackageRecoveryException(
        'Could not read the package recovery descriptor: $e',
      );
    }

    if (decoded is! Map) {
      throw const TelegramStoragePackageRecoveryException(
        'Invalid package recovery descriptor.',
      );
    }

    final root =
        Map<String, dynamic>.from(
      decoded,
    );

    if (root['version'] != _version ||
        root['kind'] != _kind ||
        root['package'] is! Map) {
      throw const TelegramStoragePackageRecoveryException(
        'Unsupported package recovery descriptor.',
      );
    }

    final data =
        Map<String, dynamic>.from(
      root['package'] as Map,
    );

    final packageId =
        _requiredString(
      data['packageId'],
      'packageId',
    );

    if (packageId !=
        journal.packageId) {
      throw const TelegramStoragePackageRecoveryException(
        'The recovery descriptor does not belong to this journal.',
      );
    }

    final parts =
        _readParts(
      data['parts'],
    );

    if (parts.isEmpty) {
      throw const TelegramStoragePackageRecoveryException(
        'The recovery descriptor contains no package parts.',
      );
    }

    final rawCatalog =
        data['catalog'];

    TelegramStorageCatalogInfo? catalog;

    if (rawCatalog is Map) {
      final catalogData =
          Map<String, dynamic>.from(
        rawCatalog,
      );

      final galleryPaths =
          journal.hasGallery
              ? <String>[]
              : _readStringList(
                  catalogData[
                    'galleryImagePaths'
                  ],
                );

      catalog =
          TelegramStorageCatalogInfo(
        modelId:
            _optionalString(
                  catalogData['modelId'],
                ) ??
                '',
        name:
            _requiredString(
          catalogData['name'],
          'catalog.name',
        ),
        studio:
            _optionalString(
          catalogData['studio'],
        ),
        category:
            _optionalString(
          catalogData['category'],
        ),
        type:
            _optionalString(
          catalogData['type'],
        ),
        scale:
            _optionalString(
          catalogData['scale'],
        ),
        height:
            _optionalString(
          catalogData['height'],
        ),
        description:
            _optionalString(
          catalogData['description'],
        ),
        tags:
            _readStringList(
          catalogData['tags'],
        ),
        galleryImagePaths:
            galleryPaths,
      );
    }

    final createdAtText =
        _requiredString(
      data['createdAt'],
      'createdAt',
    );

    final createdAt =
        DateTime.tryParse(
      createdAtText,
    );

    if (createdAt == null) {
      throw const TelegramStoragePackageRecoveryException(
        'Invalid package creation date in recovery descriptor.',
      );
    }

    final package =
        TelegramStoragePackage(
      packageId:
          packageId,
      sourceFolderName:
          _requiredString(
        data['sourceFolderName'],
        'sourceFolderName',
      ),
      sourceFolderPath:
          _optionalString(
                data['sourceFolderPath'],
              ) ??
              '',
      sourceSize:
          _requiredInt(
        data['sourceSize'],
        'sourceSize',
      ),
      archiveFileName:
          _requiredString(
        data['archiveFileName'],
        'archiveFileName',
      ),
      archiveSize:
          _requiredInt(
        data['archiveSize'],
        'archiveSize',
      ),
      archiveSha256:
          _requiredString(
        data['archiveSha256'],
        'archiveSha256',
      ),
      stagingDirectoryPath:
          stagingPath,
      manifestPath:
          _requiredString(
        data['manifestPath'],
        'manifestPath',
      ),
      createdAt:
          createdAt,
      parts:
          parts,
      catalog:
          catalog,
    );

    await _validateLocalFiles(
      package:
          package,
      journal:
          journal,
    );

    return package;
  }

  // ============================================================
  // VALIDATION
  // ============================================================

  Future<void> _validateLocalFiles({
    required TelegramStoragePackage package,
    required TelegramStorageUploadJournal journal,
  }) async {
    for (final part
        in package.parts) {
      final file =
          File(
        part.filePath,
      );

      if (!await file.exists()) {
        throw TelegramStoragePackageRecoveryException(
          'Missing local package part: ${part.fileName}',
        );
      }

      final size =
          await file.length();

      if (size != part.size) {
        throw TelegramStoragePackageRecoveryException(
          'Local package part size changed: ${part.fileName}',
        );
      }
    }

    if (!journal.hasGallery) {
      for (final imagePath
          in package.galleryImagePaths) {
        if (!await File(
          imagePath,
        ).exists()) {
          throw TelegramStoragePackageRecoveryException(
            'Gallery image is no longer available: '
            '${p.basename(imagePath)}',
          );
        }
      }
    }
  }

  // ============================================================
  // READ HELPERS
  // ============================================================

  List<TelegramStoragePackagePart> _readParts(
    dynamic raw,
  ) {
    if (raw is! List) {
      return <TelegramStoragePackagePart>[];
    }

    final result =
        <TelegramStoragePackagePart>[];

    for (final item
        in raw) {
      if (item is! Map) {
        continue;
      }

      final data =
          Map<String, dynamic>.from(
        item,
      );

      result.add(
        TelegramStoragePackagePart(
          index:
              _requiredInt(
            data['index'],
            'part.index',
          ),
          filePath:
              _requiredString(
            data['filePath'],
            'part.filePath',
          ),
          fileName:
              _requiredString(
            data['fileName'],
            'part.fileName',
          ),
          size:
              _requiredInt(
            data['size'],
            'part.size',
          ),
          sha256:
              _requiredString(
            data['sha256'],
            'part.sha256',
          ),
        ),
      );
    }

    result.sort(
      (
        a,
        b,
      ) =>
          a.index.compareTo(
        b.index,
      ),
    );

    return result;
  }

  List<String> _readStringList(
    dynamic raw,
  ) {
    if (raw is! List) {
      return <String>[];
    }

    return raw
        .map(
          (
            item,
          ) =>
              item
                  .toString()
                  .trim(),
        )
        .where(
          (
            item,
          ) =>
              item.isNotEmpty,
        )
        .toList();
  }

  String _requiredString(
    dynamic value,
    String field,
  ) {
    final result =
        _optionalString(
      value,
    );

    if (result == null) {
      throw TelegramStoragePackageRecoveryException(
        'Missing recovery field: $field',
      );
    }

    return result;
  }

  String? _optionalString(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    final result =
        value
            .toString()
            .trim();

    return result.isEmpty
        ? null
        : result;
  }

  int _requiredInt(
    dynamic value,
    String field,
  ) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    final parsed =
        int.tryParse(
      value?.toString() ?? '',
    );

    if (parsed == null) {
      throw TelegramStoragePackageRecoveryException(
        'Invalid recovery field: $field',
      );
    }

    return parsed;
  }
}

class TelegramStoragePackageRecoveryException
    implements Exception {
  final String message;

  const TelegramStoragePackageRecoveryException(
    this.message,
  );

  @override
  String toString() =>
      message;
}
