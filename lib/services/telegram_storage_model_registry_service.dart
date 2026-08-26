import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/catalog_model.dart';
import '../models/telegram_storage_upload_journal.dart';
import 'telegram_storage_upload_journal_service.dart';

class TelegramStorageModelLink {
  final String modelId;

  final String folderPath;

  final String modelName;

  final String studioName;

  final String packageId;

  final DateTime createdAt;

  final DateTime updatedAt;

  const TelegramStorageModelLink({
    required this.modelId,
    required this.folderPath,
    required this.modelName,
    required this.studioName,
    required this.packageId,
    required this.createdAt,
    required this.updatedAt,
  });

  TelegramStorageModelLink copyWith({
    String? modelId,
    String? folderPath,
    String? modelName,
    String? studioName,
    String? packageId,
  }) {
    return TelegramStorageModelLink(
      modelId:
          modelId ??
          this.modelId,
      folderPath:
          folderPath ??
          this.folderPath,
      modelName:
          modelName ??
          this.modelName,
      studioName:
          studioName ??
          this.studioName,
      packageId:
          packageId ??
          this.packageId,
      createdAt:
          createdAt,
      updatedAt:
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'modelId':
          modelId,
      'folderPath':
          folderPath,
      'modelName':
          modelName,
      'studioName':
          studioName,
      'packageId':
          packageId,
      'createdAt':
          createdAt
              .toUtc()
              .toIso8601String(),
      'updatedAt':
          updatedAt
              .toUtc()
              .toIso8601String(),
    };
  }

  factory TelegramStorageModelLink.fromJson(
    Map<String, dynamic> json,
  ) {
    final now =
        DateTime.now();

    return TelegramStorageModelLink(
      modelId:
          json['modelId']
                  ?.toString()
                  .trim() ??
              '',
      folderPath:
          json['folderPath']
                  ?.toString() ??
              '',
      modelName:
          json['modelName']
                  ?.toString() ??
              '',
      studioName:
          json['studioName']
                  ?.toString() ??
              '',
      packageId:
          json['packageId']
                  ?.toString() ??
              '',
      createdAt:
          DateTime.tryParse(
                json['createdAt']
                        ?.toString() ??
                    '',
              ) ??
              now,
      updatedAt:
          DateTime.tryParse(
                json['updatedAt']
                        ?.toString() ??
                    '',
              ) ??
              now,
    );
  }
}

class TelegramStorageModelStatus {
  final bool localAvailable;

  final String modelId;

  final TelegramStorageModelLink? link;

  final TelegramStorageUploadJournal? journal;

  const TelegramStorageModelStatus({
    required this.localAvailable,
    required this.modelId,
    required this.link,
    required this.journal,
  });

  bool get isLinked =>
      link !=
      null;

  bool get hasJournal =>
      journal !=
      null;

  bool get isStored =>
      journal?.isStored ??
      false;

  bool get isIncomplete =>
      journal !=
          null &&
      !journal!.isStored;

  String get telegramStatusLabel {
    final value =
        journal?.status;

    if (value ==
        null) {
      return 'NOT STORED';
    }

    return value.value
        .toUpperCase();
  }

  String? get packageId =>
      journal?.packageId ??
      link?.packageId;
}

class TelegramStorageModelRegistryService {
  TelegramStorageModelRegistryService._();

  static final TelegramStorageModelRegistryService instance =
      TelegramStorageModelRegistryService._();

  final TelegramStorageUploadJournalService _journalService =
      TelegramStorageUploadJournalService.instance;

  static const String _fileName =
      'storage_model_registry.json';

  static const String _recoveryDescriptorName =
      'package_recovery.json';

  String _filePath() {
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
      _fileName,
    );
  }

  String _normalizePath(
    String path,
  ) {
    return p.normalize(
      path,
    ).toLowerCase();
  }

  Future<List<TelegramStorageModelLink>>
      _loadLinks() async {
    final file =
        File(
      _filePath(),
    );

    try {
      if (!await file.exists()) {
        return <TelegramStorageModelLink>[];
      }

      final decoded =
          jsonDecode(
        await file.readAsString(),
      );

      if (decoded is! Map) {
        return <TelegramStorageModelLink>[];
      }

      final root =
          Map<String, dynamic>.from(
        decoded,
      );

      if (root['kind'] !=
          'fabularium-storage-model-registry') {
        return <TelegramStorageModelLink>[];
      }

      final version =
          root['version'];

      if (version !=
              1 &&
          version !=
              2) {
        return <TelegramStorageModelLink>[];
      }

      final rawLinks =
          root['links'];

      if (rawLinks is! List) {
        return <TelegramStorageModelLink>[];
      }

      final result =
          <TelegramStorageModelLink>[];

      for (final raw
          in rawLinks) {
        if (raw is! Map) {
          continue;
        }

        try {
          final link =
              TelegramStorageModelLink.fromJson(
            Map<String, dynamic>.from(
              raw,
            ),
          );

          if (link.folderPath
                  .trim()
                  .isEmpty ||
              link.packageId
                  .trim()
                  .isEmpty) {
            continue;
          }

          result.add(
            link,
          );
        } catch (_) {}
      }

      return result;
    } catch (_) {
      return <TelegramStorageModelLink>[];
    }
  }

  Future<void> _saveLinks(
    List<TelegramStorageModelLink> links,
  ) async {
    final file =
        File(
      _filePath(),
    );

    await file.parent.create(
      recursive:
          true,
    );

    final temp =
        File(
      '${file.path}.tmp',
    );

    final sorted =
        List<TelegramStorageModelLink>.from(
      links,
    )
          ..sort(
            (
              a,
              b,
            ) =>
                a.modelName
                    .toLowerCase()
                    .compareTo(
                      b.modelName
                          .toLowerCase(),
                    ),
          );

    const encoder =
        JsonEncoder.withIndent(
      '  ',
    );

    await temp.writeAsString(
      encoder.convert(
        <String, dynamic>{
          'version':
              2,
          'kind':
              'fabularium-storage-model-registry',
          'links':
              sorted
                  .map(
                    (
                      link,
                    ) =>
                        link.toJson(),
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

  Future<TelegramStorageModelLink>
      linkPackage({
    required CatalogModel model,
    required String modelId,
    required String packageId,
  }) async {
    final normalizedModelId =
        modelId.trim();

    if (normalizedModelId.isEmpty) {
      throw const TelegramStorageModelRegistryException(
        'A modelId is required before linking a Telegram package.',
      );
    }

    final links =
        await _loadLinks();

    final normalizedPath =
        _normalizePath(
      model.folderPath,
    );

    int existingIndex =
        links.indexWhere(
      (
        item,
      ) =>
          item.modelId ==
          normalizedModelId,
    );

    /*
     * Registry V1 migration:
     * old links had no modelId, so fall back
     * to folderPath exactly once.
     */
    if (existingIndex <
        0) {
      existingIndex =
          links.indexWhere(
        (
          item,
        ) =>
            item.modelId.isEmpty &&
            _normalizePath(
                  item.folderPath,
                ) ==
                normalizedPath,
      );
    }

    TelegramStorageModelLink link;

    if (existingIndex >=
        0) {
      link =
          links[
                  existingIndex]
              .copyWith(
        modelId:
            normalizedModelId,
        folderPath:
            model.folderPath,
        modelName:
            model.name,
        studioName:
            model.studio,
        packageId:
            packageId,
      );

      links[
          existingIndex] =
          link;
    } else {
      final now =
          DateTime.now();

      link =
          TelegramStorageModelLink(
        modelId:
            normalizedModelId,
        folderPath:
            model.folderPath,
        modelName:
            model.name,
        studioName:
            model.studio,
        packageId:
            packageId,
        createdAt:
            now,
        updatedAt:
            now,
      );

      links.add(
        link,
      );
    }

    await _saveLinks(
      links,
    );

    return link;
  }

  Future<void> unlinkPackage(
    String packageId,
  ) async {
    final links =
        await _loadLinks();

    final updated =
        links
            .where(
              (
                item,
              ) =>
                  item.packageId !=
                  packageId,
            )
            .toList();

    if (updated.length ==
        links.length) {
      return;
    }

    await _saveLinks(
      updated,
    );
  }

  Future<TelegramStorageModelStatus>
      getStatus({
    required CatalogModel model,
    required String modelId,
  }) async {
    final normalizedModelId =
        modelId.trim();

    final localAvailable =
        await Directory(
      model.folderPath,
    ).exists();

    final links =
        await _loadLinks();

    final normalizedPath =
        _normalizePath(
      model.folderPath,
    );

    TelegramStorageModelLink? link;

    for (final item
        in links) {
      if (normalizedModelId.isNotEmpty &&
          item.modelId ==
              normalizedModelId) {
        link =
            item;

        break;
      }
    }

    /*
     * Migrate old registry entries that only
     * knew folderPath.
     */
    if (link ==
        null) {
      for (final item
          in links) {
        if (_normalizePath(
              item.folderPath,
            ) ==
            normalizedPath) {
          link =
              item;

          break;
        }
      }
    }

    if (link !=
        null) {
      if (link.modelId !=
              normalizedModelId ||
          _normalizePath(
                link.folderPath,
              ) !=
              normalizedPath) {
        final index =
            links.indexOf(
          link,
        );

        final updated =
            link.copyWith(
          modelId:
              normalizedModelId,
          folderPath:
              model.folderPath,
          modelName:
              model.name,
          studioName:
              model.studio,
        );

        links[
            index] =
            updated;

        link =
            updated;

        await _saveLinks(
          links,
        );
      }

      final journal =
          await _journalService.load(
        link.packageId,
      );

      if (journal !=
          null) {
        return TelegramStorageModelStatus(
          localAvailable:
              localAvailable,
          modelId:
              normalizedModelId,
          link:
              link,
          journal:
              journal,
        );
      }

      /*
       * Clean removes the journal.
       * Remove stale registry mapping too.
       */
      await unlinkPackage(
        link.packageId,
      );
    }

    final recovered =
        await _recoverFromJournals(
      model:
          model,
      modelId:
          normalizedModelId,
    );

    if (recovered !=
        null) {
      return TelegramStorageModelStatus(
        localAvailable:
            localAvailable,
        modelId:
            normalizedModelId,
        link:
            recovered.$1,
        journal:
            recovered.$2,
      );
    }

    return TelegramStorageModelStatus(
      localAvailable:
          localAvailable,
      modelId:
          normalizedModelId,
      link:
          null,
      journal:
          null,
    );
  }

  Future<
      (
        TelegramStorageModelLink,
        TelegramStorageUploadJournal
      )?> _recoverFromJournals({
    required CatalogModel model,
    required String modelId,
  }) async {
    final journals =
        await _journalService.list();

    final normalizedPath =
        _normalizePath(
      model.folderPath,
    );

    for (final journal
        in journals) {
      final descriptor =
          await _readRecoveryDescriptor(
        journal,
      );

      if (descriptor ==
          null) {
        continue;
      }

      final descriptorModelId =
          descriptor.modelId;

      final modelIdMatches =
          modelId.isNotEmpty &&
          descriptorModelId.isNotEmpty &&
          descriptorModelId ==
              modelId;

      final pathMatches =
          descriptor.sourceFolderPath.isNotEmpty &&
          _normalizePath(
                descriptor.sourceFolderPath,
              ) ==
              normalizedPath;

      if (!modelIdMatches &&
          !pathMatches) {
        continue;
      }

      final link =
          await linkPackage(
        model:
            model,
        modelId:
            modelId,
        packageId:
            journal.packageId,
      );

      return (
        link,
        journal,
      );
    }

    return null;
  }

  Future<_RecoveryIdentity?>
      _readRecoveryDescriptor(
    TelegramStorageUploadJournal journal,
  ) async {
    final stagingPath =
        journal.stagingDirectoryPath
            .trim();

    if (stagingPath.isEmpty) {
      return null;
    }

    final file =
        File(
      p.join(
        stagingPath,
        _recoveryDescriptorName,
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

      final rawPackage =
          root['package'];

      if (rawPackage is! Map) {
        return null;
      }

      final package =
          Map<String, dynamic>.from(
        rawPackage,
      );

      final sourceFolderPath =
          package['sourceFolderPath']
                  ?.toString()
                  .trim() ??
              '';

      String modelId =
          '';

      final rawCatalog =
          package['catalog'];

      if (rawCatalog is Map) {
        final catalog =
            Map<String, dynamic>.from(
          rawCatalog,
        );

        modelId =
            catalog['modelId']
                    ?.toString()
                    .trim() ??
                '';
      }

      if (sourceFolderPath.isEmpty &&
          modelId.isEmpty) {
        return null;
      }

      return _RecoveryIdentity(
        sourceFolderPath:
            sourceFolderPath,
        modelId:
            modelId,
      );
    } catch (_) {
      return null;
    }
  }
}

class _RecoveryIdentity {
  final String sourceFolderPath;

  final String modelId;

  const _RecoveryIdentity({
    required this.sourceFolderPath,
    required this.modelId,
  });
}

class TelegramStorageModelRegistryException
    implements Exception {
  final String message;

  const TelegramStorageModelRegistryException(
    this.message,
  );

  @override
  String toString() =>
      message;
}
