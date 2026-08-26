import '../../../../models/telegram_media.dart';

class TelegramCatalogEntry {
  final String packageId;
  final int messageId;
  final String name;
  final String studio;
  final String category;
  final String type;
  final String scale;
  final String height;
  final String archiveSizeLabel;
  final int? partCount;
  final String description;
  final DateTime? publishedAt;
  final TelegramMedia coverMedia;

  const TelegramCatalogEntry({
    required this.packageId,
    required this.messageId,
    required this.name,
    required this.studio,
    required this.category,
    required this.type,
    required this.scale,
    required this.height,
    required this.archiveSizeLabel,
    required this.partCount,
    required this.description,
    required this.publishedAt,
    required this.coverMedia,
  });

  String get searchText {
    return <String>[
      name,
      studio,
      category,
      type,
      scale,
      height,
      description,
      packageId,
    ].join(' ').toLowerCase();
  }
}
