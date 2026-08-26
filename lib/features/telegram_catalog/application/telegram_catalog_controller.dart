import 'package:flutter/foundation.dart';

import '../data/telegram_catalog_repository_impl.dart';
import '../domain/entities/telegram_catalog_entry.dart';
import '../domain/repositories/telegram_catalog_repository.dart';

class TelegramCatalogController
    extends ChangeNotifier {
  final TelegramCatalogRepository repository;

  TelegramCatalogController({
    TelegramCatalogRepository? repository,
  }) : repository =
            repository ??
                TelegramCatalogRepositoryImpl();

  static const int _pageSize = 100;

  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = false;
  String channelTitle = '';
  String? error;

  List<TelegramCatalogEntry> entries =
      const <TelegramCatalogEntry>[];

  int _offsetId = 0;
  int _generation = 0;

  Future<void> load() async {
    final generation = ++_generation;

    isLoading = true;
    isLoadingMore = false;
    hasMore = false;
    error = null;
    entries =
        const <TelegramCatalogEntry>[];
    _offsetId = 0;

    notifyListeners();

    try {
      final page =
          await repository.loadPage(
        limit: _pageSize,
        offsetId: 0,
      );

      if (generation != _generation) {
        return;
      }

      channelTitle = page.channelTitle;
      entries = _mergeEntries(
        const <TelegramCatalogEntry>[],
        page.entries,
      );
      _offsetId = page.nextOffsetId;
      hasMore = page.hasMore;
      isLoading = false;

      notifyListeners();
    } catch (e) {
      if (generation != _generation) {
        return;
      }

      isLoading = false;
      error = e.toString();

      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (isLoading ||
        isLoadingMore ||
        !hasMore) {
      return;
    }

    final generation = _generation;

    isLoadingMore = true;
    error = null;

    notifyListeners();

    try {
      final page =
          await repository.loadPage(
        limit: _pageSize,
        offsetId: _offsetId,
      );

      if (generation != _generation) {
        return;
      }

      if (page.channelTitle.isNotEmpty) {
        channelTitle =
            page.channelTitle;
      }

      entries = _mergeEntries(
        entries,
        page.entries,
      );
      _offsetId = page.nextOffsetId;
      hasMore = page.hasMore;
      isLoadingMore = false;

      notifyListeners();
    } catch (e) {
      if (generation != _generation) {
        return;
      }

      isLoadingMore = false;
      error = e.toString();

      notifyListeners();
    }
  }

  List<TelegramCatalogEntry>
      _mergeEntries(
    List<TelegramCatalogEntry> current,
    List<TelegramCatalogEntry> incoming,
  ) {
    final byPackageId =
        <String, TelegramCatalogEntry>{};

    for (final entry in current) {
      byPackageId[entry.packageId] =
          entry;
    }

    for (final entry in incoming) {
      final existing =
          byPackageId[entry.packageId];

      if (existing == null ||
          entry.messageId >
              existing.messageId) {
        byPackageId[entry.packageId] =
            entry;
      }
    }

    final result =
        byPackageId.values.toList()
          ..sort(
            (a, b) =>
                b.messageId.compareTo(
              a.messageId,
            ),
          );

    return result;
  }
}
