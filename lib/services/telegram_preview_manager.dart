import 'dart:async';
import 'dart:collection';

import '../models/telegram_media.dart';
import 'download_queue_service.dart';
import 'telegram_download_worker.dart';
import 'telegram_file_service.dart';
import 'telegram_performance_coordinator.dart';

class TelegramPreviewManager {
  TelegramPreviewManager._();

  static final TelegramPreviewManager instance =
      TelegramPreviewManager._();

  final TelegramDownloadWorker _worker =
      TelegramDownloadWorker.instance;

  final DownloadQueueService _downloadQueue =
      DownloadQueueService.instance;

  final TelegramFileService _files =
      TelegramFileService.instance;

  final TelegramPerformanceCoordinator _performance =
      TelegramPerformanceCoordinator.instance;

  final Map<String, String> _memoryCache =
      <String, String>{};

  final Map<String, _InFlightPreview> _inFlight =
      <String, _InFlightPreview>{};

  final Queue<_PreviewRequest> _queue =
      Queue<_PreviewRequest>();

  final Queue<_PreviewRequest> _staleQueue =
      Queue<_PreviewRequest>();

  bool _processing =
      false;

  bool _cancellingStale =
      false;

  bool _needsInitialDelay =
      true;

  int _generation =
      0;

  Future<void>? _cacheMaintenanceFuture;

  DateTime? _lastCacheMaintenance;

  static const Duration _betweenRequests =
      Duration(
    milliseconds: 140,
  );

  static const Duration _initialDelay =
      Duration(
    milliseconds: 450,
  );

  static const Duration _performanceWait =
      Duration(
    milliseconds: 100,
  );

  static const Duration _staleCancellationDelay =
      Duration(
    milliseconds: 8,
  );

  /*
   * Não precisamos varrer o disco toda vez
   * que uma tela é aberta.
   */
  static const Duration _cacheMaintenanceInterval =
      Duration(
    minutes: 30,
  );

  // ============================================================
  // CACHE
  // ============================================================

  String? cachedPath(
    TelegramMedia media,
  ) {
    return _memoryCache[
        media.cacheKey];
  }

  void _scheduleCacheMaintenance() {
    if (_cacheMaintenanceFuture !=
        null) {
      return;
    }

    final now =
        DateTime.now();

    final last =
        _lastCacheMaintenance;

    if (last != null &&
        now.difference(
              last,
            ) <
            _cacheMaintenanceInterval) {
      return;
    }

    /*
     * Arquivos atualmente conhecidos pelo cache
     * em memória não podem ser removidos nesta
     * rodada.
     */
    final protectedPaths =
        _memoryCache.values.toSet();

    late final Future<void>
        future;

    future = _files.cleanupPreviewCache(
      maxBytes:
          TelegramFileService
              .previewCacheMaxBytes,
      maxAge:
          TelegramFileService
              .previewCacheMaxAge,
      protectedPaths:
          protectedPaths,
    ).whenComplete(
      () {
        _lastCacheMaintenance =
            DateTime.now();

        if (identical(
          _cacheMaintenanceFuture,
          future,
        )) {
          _cacheMaintenanceFuture =
              null;
        }
      },
    );

    _cacheMaintenanceFuture =
        future;
  }

  Future<void> _waitForCacheMaintenance() async {
    final maintenance =
        _cacheMaintenanceFuture;

    if (maintenance == null) {
      return;
    }

    /*
     * Impede que o preview worker comece a usar
     * um arquivo enquanto a manutenção física
     * está avaliando/removendo aquele mesmo
     * arquivo.
     */
    try {
      await maintenance;
    } catch (_) {
      /*
       * Manutenção de cache é best effort.
       */
    }
  }

  // ============================================================
  // PREVIEW REQUEST
  // ============================================================

  Future<String> getPreview(
    TelegramMedia media,
  ) {
    final key =
        media.cacheKey;

    final cached =
        _memoryCache[key];

    if (cached != null) {
      return Future<String>.value(
        cached,
      );
    }

    final existing =
        _inFlight[key];

    if (existing != null &&
        existing.generation ==
            _generation) {
      return existing.future;
    }

    final completer =
        Completer<String>();

    final inFlight =
        _InFlightPreview(
      generation:
          _generation,
      future:
          completer.future,
    );

    _inFlight[key] =
        inFlight;

    _queue.addLast(
      _PreviewRequest(
        media:
            media,
        completer:
            completer,
        generation:
            _generation,
        inFlight:
            inFlight,
      ),
    );

    _startProcessing();

    return completer.future;
  }

  // ============================================================
  // PROCESSING
  // ============================================================

  void _startProcessing() {
    if (_processing) {
      return;
    }

    unawaited(
      _processQueue(),
    );
  }

  Future<void> _processQueue() async {
    if (_processing) {
      return;
    }

    _processing =
        true;

    try {
      while (_queue.isNotEmpty) {
        final request =
            _queue.first;

        if (request.generation !=
            _generation) {
          _moveFirstRequestToStaleQueue();

          continue;
        }

        // --------------------------------------------------------
        // INITIAL SCREEN DELAY
        // --------------------------------------------------------

        if (_needsInitialDelay) {
          _needsInitialDelay =
              false;

          await Future<void>.delayed(
            _initialDelay,
          );

          if (request.generation !=
              _generation) {
            continue;
          }

          if (_queue.isEmpty) {
            break;
          }

          if (!identical(
            _queue.first,
            request,
          )) {
            continue;
          }
        }

        // --------------------------------------------------------
        // PERFORMANCE WINDOW
        // --------------------------------------------------------

        await _waitForPerformanceWindow(
          request,
        );

        if (request.generation !=
            _generation) {
          continue;
        }

        if (_queue.isEmpty) {
          break;
        }

        if (!identical(
          _queue.first,
          request,
        )) {
          continue;
        }

        // --------------------------------------------------------
        // PHYSICAL CACHE MAINTENANCE
        // --------------------------------------------------------

        await _waitForCacheMaintenance();

        /*
         * A geração pode ter mudado enquanto
         * aguardávamos a limpeza física.
         */
        if (request.generation !=
            _generation) {
          continue;
        }

        if (_queue.isEmpty) {
          break;
        }

        if (!identical(
          _queue.first,
          request,
        )) {
          continue;
        }

        /*
         * Só removemos da fila imediatamente
         * antes do download real.
         */
        _queue.removeFirst();

        final key =
            request.media.cacheKey;

        // --------------------------------------------------------
        // MEMORY CACHE
        // --------------------------------------------------------

        final cached =
            _memoryCache[key];

        if (cached != null) {
          _removeInFlightIfSame(
            request,
          );

          if (!request
              .completer
              .isCompleted) {
            request.completer.complete(
              cached,
            );
          }

          continue;
        }

        // --------------------------------------------------------
        // DOWNLOAD
        // --------------------------------------------------------

        try {
          final path =
              await _worker
                  .downloadPreview(
            request.media,
          );

          _memoryCache[key] =
              path;

          if (request.generation !=
              _generation) {
            if (!request
                .completer
                .isCompleted) {
              request.completer.completeError(
                const TelegramPreviewCancelledException(),
              );
            }
          } else {
            if (!request
                .completer
                .isCompleted) {
              request.completer.complete(
                path,
              );
            }
          }
        } catch (
          error,
          stackTrace
        ) {
          if (!request
              .completer
              .isCompleted) {
            request.completer.completeError(
              error,
              stackTrace,
            );
          }
        } finally {
          _removeInFlightIfSame(
            request,
          );
        }

        if (_queue.isNotEmpty) {
          await Future<void>.delayed(
            _betweenRequests,
          );
        }
      }
    } finally {
      _processing =
          false;

      if (_queue.isNotEmpty) {
        _startProcessing();
      }
    }
  }

  // ============================================================
  // PERFORMANCE
  // ============================================================

  Future<void> _waitForPerformanceWindow(
    _PreviewRequest request,
  ) async {
    while (true) {
      if (request.generation !=
          _generation) {
        return;
      }

      final largeDownloadRunning =
          _downloadQueue.currentTask !=
              null;

      final userInteracting =
          _performance.isInteractive;

      if (!largeDownloadRunning ||
          !userInteracting) {
        return;
      }

      await Future<void>.delayed(
        _performanceWait,
      );
    }
  }

  // ============================================================
  // GENERATIONS
  // ============================================================

  void prepareForScreen() {
    _advanceGeneration(
      resetInitialDelay:
          true,
    );

    /*
     * Aproveitamos a abertura de uma tela Telegram
     * para fazer manutenção oportunista do cache.
     */
    _scheduleCacheMaintenance();
  }

  void cancelPending({
    bool resetInitialDelay = true,
  }) {
    _advanceGeneration(
      resetInitialDelay:
          resetInitialDelay,
    );
  }

  void _advanceGeneration({
    required bool resetInitialDelay,
  }) {
    _generation++;

    if (resetInitialDelay) {
      _needsInitialDelay =
          true;
    }

    _moveQueuedRequestsToStaleQueue();

    _startStaleCancellation();

    _startProcessing();
  }

  // ============================================================
  // STALE REQUESTS
  // ============================================================

  void _moveQueuedRequestsToStaleQueue() {
    if (_queue.isEmpty) {
      return;
    }

    final currentRequests =
        Queue<_PreviewRequest>();

    while (_queue.isNotEmpty) {
      final request =
          _queue.removeFirst();

      if (request.generation ==
          _generation) {
        currentRequests.addLast(
          request,
        );

        continue;
      }

      _removeInFlightIfSame(
        request,
      );

      _staleQueue.addLast(
        request,
      );
    }

    _queue.addAll(
      currentRequests,
    );
  }

  void _moveFirstRequestToStaleQueue() {
    if (_queue.isEmpty) {
      return;
    }

    final request =
        _queue.removeFirst();

    _removeInFlightIfSame(
      request,
    );

    _staleQueue.addLast(
      request,
    );

    _startStaleCancellation();
  }

  void _startStaleCancellation() {
    if (_cancellingStale ||
        _staleQueue.isEmpty) {
      return;
    }

    unawaited(
      _cancelStaleRequests(),
    );
  }

  Future<void> _cancelStaleRequests() async {
    if (_cancellingStale) {
      return;
    }

    _cancellingStale =
        true;

    try {
      while (_staleQueue.isNotEmpty) {
        final request =
            _staleQueue.removeFirst();

        if (!request
            .completer
            .isCompleted) {
          request.completer.completeError(
            const TelegramPreviewCancelledException(),
          );
        }

        if (_staleQueue.isNotEmpty) {
          await Future<void>.delayed(
            _staleCancellationDelay,
          );
        }
      }
    } finally {
      _cancellingStale =
          false;

      if (_staleQueue.isNotEmpty) {
        _startStaleCancellation();
      }
    }
  }

  // ============================================================
  // IN FLIGHT
  // ============================================================

  void _removeInFlightIfSame(
    _PreviewRequest request,
  ) {
    final current =
        _inFlight[
            request.media.cacheKey];

    if (identical(
      current,
      request.inFlight,
    )) {
      _inFlight.remove(
        request.media.cacheKey,
      );
    }
  }

  // ============================================================
  // MEMORY CACHE
  // ============================================================

  void clearMemoryCache() {
    _memoryCache.clear();
  }
}

class _PreviewRequest {
  final TelegramMedia media;

  final Completer<String>
      completer;

  final int generation;

  final _InFlightPreview
      inFlight;

  const _PreviewRequest({
    required this.media,
    required this.completer,
    required this.generation,
    required this.inFlight,
  });
}

class _InFlightPreview {
  final int generation;

  final Future<String> future;

  const _InFlightPreview({
    required this.generation,
    required this.future,
  });
}

class TelegramPreviewCancelledException
    implements Exception {
  const TelegramPreviewCancelledException();

  @override
  String toString() =>
      'Preview cancelled.';
}