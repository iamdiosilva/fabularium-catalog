import '../entities/telegram_catalog_entry.dart';

abstract class TelegramCatalogRepository {
  Future<TelegramCatalogPageResult> loadPage({
    int limit = 100,
    int offsetId = 0,
  });
}

class TelegramCatalogPageResult {
  final String channelTitle;
  final List<TelegramCatalogEntry> entries;
  final int nextOffsetId;
  final bool hasMore;

  const TelegramCatalogPageResult({
    required this.channelTitle,
    required this.entries,
    required this.nextOffsetId,
    required this.hasMore,
  });
}
