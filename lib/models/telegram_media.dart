import 'package:t/t.dart' as t;

enum TelegramMediaType {
  photo,
  document,
}

class TelegramMedia {
  final TelegramMediaType type;
  final String cacheKey;
  final String fileName;
  final String mimeType;
  final int size;
  final int dcId;
  final t.InputFileLocationBase location;
  final t.InputFileLocationBase? previewLocation;
  final int? previewSize;

  const TelegramMedia({
    required this.type,
    required this.cacheKey,
    required this.fileName,
    required this.mimeType,
    required this.size,
    required this.dcId,
    required this.location,
    required this.previewLocation,
    required this.previewSize,
  });

  bool get isPhoto => type == TelegramMediaType.photo;
  bool get isDocument => type == TelegramMediaType.document;
  bool get isImage => isPhoto || mimeType.startsWith('image/');
  bool get hasPreview => previewLocation != null;
}
