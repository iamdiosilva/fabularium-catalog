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

  Map<String, dynamic> toManifestJson({
    int? messageId,
  }) {
    return <String, dynamic>{
      'index': index,
      'fileName': fileName,
      'size': size,
      'sha256': sha256,
      'messageId': messageId,
    };
  }
}

class TelegramStoragePackage {
  final String packageId;

  final String sourceFolderName;

  final int sourceSize;

  final String archiveFileName;

  final int archiveSize;

  final String archiveSha256;

  final String stagingDirectoryPath;

  final String manifestPath;

  final DateTime createdAt;

  final List<TelegramStoragePackagePart> parts;

  const TelegramStoragePackage({
    required this.packageId,
    required this.sourceFolderName,
    required this.sourceSize,
    required this.archiveFileName,
    required this.archiveSize,
    required this.archiveSha256,
    required this.stagingDirectoryPath,
    required this.manifestPath,
    required this.createdAt,
    required this.parts,
  });

  bool get isSplit =>
      parts.length > 1;

  int get partCount =>
      parts.length;

  int get totalUploadSize {
    int result = 0;

    for (final part in parts) {
      result += part.size;
    }

    return result;
  }

  Map<String, dynamic> toManifestJson({
    int? channelId,
    String? channelTitle,
    Map<int, int?> messageIds =
        const <int, int?>{},
  }) {
    return <String, dynamic>{
      'version': 1,
      'kind':
          'fabularium-storage-package',
      'packageId':
          packageId,
      'createdAt':
          createdAt
              .toUtc()
              .toIso8601String(),
      'source': <String, dynamic>{
        'folderName':
            sourceFolderName,
        'size':
            sourceSize,
      },
      'archive': <String, dynamic>{
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
      'telegram': <String, dynamic>{
        'channelId':
            channelId,
        'channelTitle':
            channelTitle,
      },
      'parts':
          parts
              .map(
                (part) =>
                    part.toManifestJson(
                  messageId:
                      messageIds[
                        part.index
                      ],
                ),
              )
              .toList(),
    };
  }
}