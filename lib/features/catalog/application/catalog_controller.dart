import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/catalog_model.dart';
import '../data/repositories/file_system_catalog_repository.dart';
import '../data/repositories/local_telegram_status_repository.dart';
import '../domain/entities/catalog_telegram_status.dart';
import '../domain/repositories/catalog_repository.dart';
import '../domain/repositories/catalog_telegram_status_repository.dart';

class CatalogController extends ChangeNotifier {
  final String fabulariumPath;
  final CatalogRepository catalogRepository;
  final CatalogTelegramStatusRepository telegramStatusRepository;

  CatalogController({
    required this.fabulariumPath,
    CatalogRepository? catalogRepository,
    CatalogTelegramStatusRepository? telegramStatusRepository,
  })  : catalogRepository =
            catalogRepository ?? FileSystemCatalogRepository(),
        telegramStatusRepository =
            telegramStatusRepository ?? LocalTelegramStatusRepository();

  bool isLoading = true;
  String? error;
  List<CatalogStudio> studios = const <CatalogStudio>[];
  final Map<String, CatalogTelegramStatus> _telegramStatuses =
      <String, CatalogTelegramStatus>{};

  int _generation = 0;

  CatalogTelegramStatus telegramStatusFor(CatalogModel model) {
    return _telegramStatuses[_key(model)] ??
        const CatalogTelegramStatus.checking();
  }

  Future<void> load() async {
    final generation = ++_generation;
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final loaded = await catalogRepository.loadCatalog(fabulariumPath);
      if (generation != _generation) return;

      studios = loaded;
      isLoading = false;
      _telegramStatuses
        ..clear()
        ..addEntries(
          _allModels().map(
            (model) => MapEntry(
              _key(model),
              const CatalogTelegramStatus.checking(),
            ),
          ),
        );
      notifyListeners();

      unawaited(_refreshTelegramStatuses(generation));
    } catch (e) {
      if (generation != _generation) return;
      error = e.toString();
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshTelegramStatus(CatalogModel model) async {
    final key = _key(model);
    _telegramStatuses[key] = const CatalogTelegramStatus.checking();
    notifyListeners();

    try {
      final local = await telegramStatusRepository.readLocalStatus(model);
      _telegramStatuses[key] = local;
      notifyListeners();

      if (local.state == CatalogTelegramSyncState.uploaded) {
        final verified =
            await telegramStatusRepository.verifyStoredStatus(model);
        _telegramStatuses[key] = verified;
        notifyListeners();
      }
    } catch (e) {
      _telegramStatuses[key] = CatalogTelegramStatus(
        state: CatalogTelegramSyncState.verificationUnavailable,
        detail: e.toString(),
      );
      notifyListeners();
    }
  }

  Future<void> _refreshTelegramStatuses(int generation) async {
    for (final model in _allModels()) {
      if (generation != _generation) return;

      final key = _key(model);
      try {
        final local = await telegramStatusRepository.readLocalStatus(model);
        if (generation != _generation) return;
        _telegramStatuses[key] = local;
        notifyListeners();

        if (local.state == CatalogTelegramSyncState.uploaded) {
          final verified =
              await telegramStatusRepository.verifyStoredStatus(model);
          if (generation != _generation) return;
          _telegramStatuses[key] = verified;
          notifyListeners();
        }
      } catch (e) {
        if (generation != _generation) return;
        _telegramStatuses[key] = CatalogTelegramStatus(
          state: CatalogTelegramSyncState.verificationUnavailable,
          detail: e.toString(),
        );
        notifyListeners();
      }
    }
  }

  Iterable<CatalogModel> _allModels() sync* {
    for (final studio in studios) {
      yield* studio.models;
    }
  }

  String _key(CatalogModel model) => model.folderPath.toLowerCase();
}
