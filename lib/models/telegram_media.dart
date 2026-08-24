import 'package:t/t.dart' as t;

enum TelegramMediaType {
  photo,
  document,
}

class TelegramMedia {
  final TelegramMediaType type;

  /// Nome usado para cache local.
  final String cacheKey;

  /// Nome que será usado ao salvar em Downloads.
  final String fileName;

  final String mimeType;

  /// Tamanho do arquivo original.
  final int size;

  /// Data Center informado pelo Telegram.
  final int dcId;

  /// Localização do arquivo original.
  final t.InputFileLocationBase location;

  /// Localização de thumbnail/preview, quando disponível.
  final t.InputFileLocationBase? previewLocation;

  /// Tamanho conhecido do preview.
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

  bool get isPhoto =>
      type == TelegramMediaType.photo;

  bool get isDocument =>
      type == TelegramMediaType.document;

  bool get isImage =>
      isPhoto || mimeType.startsWith('image/');

  bool get hasPreview =>
      previewLocation != null;
}