import 'package:path/path.dart' as p;

class TelegramStorageCatalogInfo {
  final String modelId;

  final String name;

  final String? studio;

  final String? category;

  final String? type;

  final String? scale;

  final String? height;

  final String? description;

  final List<String> tags;

  final List<String> galleryImagePaths;

  const TelegramStorageCatalogInfo({
    this.modelId = '',
    required this.name,
    required this.studio,
    required this.category,
    required this.type,
    required this.scale,
    required this.height,
    required this.description,
    required this.tags,
    required this.galleryImagePaths,
  });

  int get galleryImageCount =>
      galleryImagePaths.length;

  List<String> get galleryFileNames =>
      galleryImagePaths
          .map(
            p.basename,
          )
          .toList();

  Map<String, dynamic> toManifestJson() {
    return <String, dynamic>{
      if (modelId
          .trim()
          .isNotEmpty)
        'modelId':
            modelId,
      'name':
          name,
      'studio':
          studio,
      'category':
          category,
      'type':
          type,
      'scale':
          scale,
      'height':
          height,
      'description':
          description,
      'tags':
          tags,
    };
  }
}

class TelegramStoragePackagePart {
  final int index;

  final String filePath;

  final String fileName;

  final int size;

  final String sha256;

  const TelegramStoragePackagePart({
    required this.index,
    required this.filePath,
    required this.fileName,
    required this.size,
    required this.sha256,
  });

  Map<String, dynamic> toManifestJson() {
    return <String, dynamic>{
      'index':
          index,
      'fileName':
          fileName,
      'size':
          size,
      'sha256':
          sha256,
    };
  }
}

class TelegramStoragePackage {
  final String packageId;

  final String sourceFolderName;

  final String sourceFolderPath;

  final int sourceSize;

  final String archiveFileName;

  final int archiveSize;

  final String archiveSha256;

  final String stagingDirectoryPath;

  final String manifestPath;

  final DateTime createdAt;

  final List<TelegramStoragePackagePart> parts;

  final TelegramStorageCatalogInfo? catalog;

  const TelegramStoragePackage({
    required this.packageId,
    required this.sourceFolderName,
    this.sourceFolderPath = '',
    required this.sourceSize,
    required this.archiveFileName,
    required this.archiveSize,
    required this.archiveSha256,
    required this.stagingDirectoryPath,
    required this.manifestPath,
    required this.createdAt,
    required this.parts,
    this.catalog,
  });

  bool get isSplit =>
      parts.length >
      1;

  int get partCount =>
      parts.length;

  String get displayName =>
      catalog?.name ??
      sourceFolderName;

  String get modelId =>
      catalog?.modelId ??
      '';

  List<String> get galleryImagePaths =>
      catalog?.galleryImagePaths ??
      const <String>[];

  int get galleryImageCount =>
      galleryImagePaths.length;

  int get totalUploadSize {
    int result =
        0;

    for (final part
        in parts) {
      result +=
          part.size;
    }

    return result;
  }

  Map<String, dynamic> toManifestJson({
    int? channelId,
    String? channelTitle,
  }) {
    final catalogInfo =
        catalog;

    return <String, dynamic>{
      'version':
          2,
      'kind':
          'fabularium-storage-package',
      'packageId':
          packageId,
      'createdAt':
          createdAt
              .toUtc()
              .toIso8601String(),
      'catalog':
          catalogInfo
                  ?.toManifestJson() ??
              <String, dynamic>{
                'name':
                    sourceFolderName,
              },
      'gallery':
          <String, dynamic>{
        'count':
            galleryImageCount,
        'files':
            catalogInfo
                    ?.galleryFileNames ??
                const <String>[],
      },
      'source':
          <String, dynamic>{
        'folderName':
            sourceFolderName,
        'size':
            sourceSize,
      },
      'archive':
          <String, dynamic>{
        'fileName':
            archiveFileName,
        'size':
            archiveSize,
        'sha256':
            archiveSha256,
        'split':
            isSplit,
        'partCount':
            partCount,
      },
      'telegram':
          <String, dynamic>{
        'channelId':
            channelId,
        'channelTitle':
            channelTitle,
      },
      'parts':
          parts
              .map(
                (
                  part,
                ) =>
                    part.toManifestJson(),
              )
              .toList(),
    };
  }
}
