import 'dart:async';
import 'dart:math';

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

  static const int _localStatusBatchSize = 12;
  static const int _remoteVerificationWorkers = 2;
  static const Duration _remoteVerificationCacheTtl = Duration(
    minutes: 5,
  );

  bool isLoading = true;
  bool isRefreshingTelegram = false;
  String? error;
  List<CatalogStudio> studios = const <CatalogStudio>[];

  final Map<String, CatalogTelegramStatus> _telegramStatuses =
      <String, CatalogTelegramStatus>{};

  final Map<String, _CachedTelegramStatus> _remoteVerificationCache =
      <String, _CachedTelegramStatus>{};

  int _generation = 0;

  CatalogTelegramStatus telegramStatusFor(
    CatalogModel model,
  ) {
    return _telegramStatuses[_key(model)] ??
        const CatalogTelegramStatus.checking();
  }

  Future<void> load() async {
    final generation = ++_generation;

    isLoading = true;
    isRefreshingTelegram = false;
    error = null;

    notifyListeners();

    try {
      final loaded = await catalogRepository.loadCatalog(
        fabulariumPath,
      );

      if (generation != _generation) {
        return;
      }

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

      unawaited(
        _refreshTelegramStatuses(
          generation,
          forceRemoteVerification: false,
        ),
      );
    } catch (e) {
      if (generation != _generation) {
        return;
      }

      error = e.toString();
      isLoading = false;
      isRefreshingTelegram = false;

      notifyListeners();
    }
  }

  Future<void> refreshAllTelegramStatuses() async {
    final generation = _generation;

    if (isLoading || generation <= 0) {
      return;
    }

    _remoteVerificationCache.clear();

    await _refreshTelegramStatuses(
      generation,
      forceRemoteVerification: true,
    );
  }

  Future<void> refreshTelegramStatus(
    CatalogModel model,
  ) async {
    final key = _key(model);

    _telegramStatuses[key] =
        const CatalogTelegramStatus.checking();

    notifyListeners();

    try {
      final local =
          await telegramStatusRepository.readLocalStatus(
        model,
      );

      _telegramStatuses[key] = local;
      notifyListeners();

      final packageId = local.packageId;

      if (local.state != CatalogTelegramSyncState.uploaded ||
          packageId == null ||
          packageId.isEmpty) {
        if (packageId != null) {
          _remoteVerificationCache.remove(
            packageId,
          );
        }

        return;
      }

      _remoteVerificationCache.remove(
        packageId,
      );

      final verified =
          await telegramStatusRepository.verifyStoredStatus(
        model,
      );

      _telegramStatuses[key] = verified;

      _cacheRemoteStatus(
        verified,
      );

      notifyListeners();
    } catch (e) {
      _telegramStatuses[key] =
          CatalogTelegramStatus(
        state:
            CatalogTelegramSyncState.verificationUnavailable,
        detail: e.toString(),
      );

      notifyListeners();
    }
  }

  Future<void> _refreshTelegramStatuses(
    int generation, {
    required bool forceRemoteVerification,
  }) async {
    if (generation != _generation) {
      return;
    }

    isRefreshingTelegram = true;
    notifyListeners();

    try {
      final models = _allModels().toList();
      final storedModels = <CatalogModel>[];

      for (var offset = 0;
          offset < models.length;
          offset += _localStatusBatchSize) {
        if (generation != _generation) {
          return;
        }

        final end = min<int>(
          offset + _localStatusBatchSize,
          models.length,
        );

        final batch = models.sublist(
          offset,
          end,
        );

        final results = await Future.wait(
          batch.map(
            (model) async {
              try {
                final status =
                    await telegramStatusRepository
                        .readLocalStatus(
                  model,
                );

                return _LocalStatusResult(
                  model: model,
                  status: status,
                );
              } catch (e) {
                return _LocalStatusResult(
                  model: model,
                  status: CatalogTelegramStatus(
                    state: CatalogTelegramSyncState
                        .verificationUnavailable,
                    detail: e.toString(),
                  ),
                );
              }
            },
          ),
        );

        if (generation != _generation) {
          return;
        }

        for (final result in results) {
          final status = result.status;

          _telegramStatuses[
              _key(result.model)] = status;

          if (status.state ==
                  CatalogTelegramSyncState.uploaded &&
              status.packageId != null &&
              status.packageId!.isNotEmpty) {
            final cached = forceRemoteVerification
                ? null
                : _cachedRemoteStatus(
                    status.packageId!,
                  );

            if (cached != null) {
              _telegramStatuses[
                  _key(result.model)] = cached;

              continue;
            }

            storedModels.add(
              result.model,
            );
          }
        }

        notifyListeners();
      }

      await _verifyStoredModels(
        models: storedModels,
        generation: generation,
      );
    } finally {
      if (generation == _generation) {
        isRefreshingTelegram = false;
        notifyListeners();
      }
    }
  }

  Future<void> _verifyStoredModels({
    required List<CatalogModel> models,
    required int generation,
  }) async {
    if (models.isEmpty) {
      return;
    }

    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        if (generation != _generation) {
          return;
        }

        final index = nextIndex;

        if (index >= models.length) {
          return;
        }

        nextIndex++;

        final model = models[index];
        final key = _key(model);
        final current = _telegramStatuses[key];

        if (current == null ||
            current.state !=
                CatalogTelegramSyncState.uploaded) {
          continue;
        }

        try {
          final verified =
              await telegramStatusRepository
                  .verifyStoredStatus(
            model,
          );

          if (generation != _generation) {
            return;
          }

          _telegramStatuses[key] = verified;

          _cacheRemoteStatus(
            verified,
          );

          notifyListeners();
        } catch (e) {
          if (generation != _generation) {
            return;
          }

          final fallback =
              CatalogTelegramStatus(
            state: CatalogTelegramSyncState
                .verificationUnavailable,
            packageId: current.packageId,
            detail: e.toString(),
          );

          _telegramStatuses[key] = fallback;

          _cacheRemoteStatus(
            fallback,
          );

          notifyListeners();
        }
      }
    }

    final workerCount = min<int>(
      _remoteVerificationWorkers,
      models.length,
    );

    await Future.wait(
      List<Future<void>>.generate(
        workerCount,
        (_) => worker(),
      ),
    );
  }

  CatalogTelegramStatus? _cachedRemoteStatus(
    String packageId,
  ) {
    final cached =
        _remoteVerificationCache[packageId];

    if (cached == null) {
      return null;
    }

    final age = DateTime.now().difference(
      cached.checkedAt,
    );

    if (age > _remoteVerificationCacheTtl) {
      _remoteVerificationCache.remove(
        packageId,
      );

      return null;
    }

    return cached.status;
  }

  void _cacheRemoteStatus(
    CatalogTelegramStatus status,
  ) {
    final packageId = status.packageId;

    if (packageId == null ||
        packageId.isEmpty) {
      return;
    }

    _remoteVerificationCache[packageId] =
        _CachedTelegramStatus(
      status: status,
      checkedAt: DateTime.now(),
    );
  }

  Iterable<CatalogModel> _allModels() sync* {
    for (final studio in studios) {
      yield* studio.models;
    }
  }

  String _key(
    CatalogModel model,
  ) {
    return model.folderPath.toLowerCase();
  }
}

class _LocalStatusResult {
  final CatalogModel model;
  final CatalogTelegramStatus status;

  const _LocalStatusResult({
    required this.model,
    required this.status,
  });
}

class _CachedTelegramStatus {
  final CatalogTelegramStatus status;
  final DateTime checkedAt;

  const _CachedTelegramStatus({
    required this.status,
    required this.checkedAt,
  });
}
