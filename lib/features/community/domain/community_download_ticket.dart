class CommunityDownloadPart {
  final int partIndex;
  final int messageId;
  final int size;
  final String sha256;

  const CommunityDownloadPart({
    required this.partIndex,
    required this.messageId,
    required this.size,
    required this.sha256,
  });

  factory CommunityDownloadPart.fromJson(Map<String, dynamic> json) {
    return CommunityDownloadPart(
      partIndex: _readInt(json['partIndex']),
      messageId: _readInt(json['messageId']),
      size: _readInt(json['size']),
      sha256: json['sha256']?.toString() ?? '',
    );
  }
}

class CommunityDownloadTicket {
  final String modelId;
  final String packageId;
  final String filesUsername;
  final String archiveExtension;
  final String archiveSha256;
  final int archiveSize;
  final List<CommunityDownloadPart> parts;

  const CommunityDownloadTicket({
    required this.modelId,
    required this.packageId,
    required this.filesUsername,
    required this.archiveExtension,
    required this.archiveSha256,
    required this.archiveSize,
    required this.parts,
  });

  factory CommunityDownloadTicket.fromJson(Map<String, dynamic> json) {
    final parts = <CommunityDownloadPart>[];
    final rawParts = json['parts'];

    if (rawParts is List) {
      for (final raw in rawParts) {
        if (raw is Map) {
          parts.add(
            CommunityDownloadPart.fromJson(
              Map<String, dynamic>.from(raw),
            ),
          );
        }
      }
    }

    parts.sort((a, b) => a.partIndex.compareTo(b.partIndex));

    return CommunityDownloadTicket(
      modelId: json['modelId']?.toString() ?? '',
      packageId: json['packageId']?.toString() ?? '',
      filesUsername: json['filesUsername']?.toString() ?? '',
      archiveExtension: json['archiveExtension']?.toString() ?? 'bin',
      archiveSha256: json['archiveSha256']?.toString() ?? '',
      archiveSize: _readInt(json['archiveSize']),
      parts: parts,
    );
  }
}

int _readInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
