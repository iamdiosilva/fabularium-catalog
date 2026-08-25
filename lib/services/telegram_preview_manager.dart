import 'dart:async';
import 'dart:collection';

import '../models/telegram_media.dart';
import 'download_queue_service.dart';
import 'telegram_download_worker.dart';
import 'telegram_performance_coordinator.dart';

class TelegramPreviewManager {
  TelegramPreviewManager._();

  static final TelegramPreviewManager instance =
      TelegramPreviewManager._();

  final TelegramDownloadWorker _worker =
      TelegramDownloadWorker.instance;

  final DownloadQueueService _downloadQueue =
      DownloadQueueService.instance;

  final TelegramPerformanceCoordinator _performance =
      TelegramPerformanceCoordinator.instance;

  final Map<String, String> _memoryCache =
      <String, String>{};

  final Map<String, _InFlightPreview> _inFlight =
      <String, _InFlightPreview>{};

  /*
   * Fila principal.
   *
   * Queue.removeFirst() é O(1), diferente do
   * List.removeAt(0), que precisa deslocar os
   * elementos restantes.
   */
  final Queue<_PreviewRequest> _queue =
      Queue<_PreviewRequest>();

  /*
   * Pedidos pertencentes a telas antigas são
   * retirados imediatamente da fila principal.
   *
   * Seus Futures são cancelados gradualmente
   * nesta fila separada para evitar uma grande
   * sequência de completions no mesmo ciclo.
   */
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

  // ============================================================
  // CACHE
  // ============================================================

  String? cachedPath(
    TelegramMedia media,
  ) {
    return _memoryCache[
        media.cacheKey];
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

    /*
     * Se a mesma preview já está sendo carregada
     * para a tela atual, compartilhamos o mesmo
     * Future.
     */
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

        /*
         * Segurança extra.
         *
         * Normalmente pedidos antigos já terão
         * sido movidos por _advanceGeneration(),
         * mas uma mudança de geração pode acontecer
         * enquanto este Future está aguardando.
         */
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

          /*
           * Durante o delay o usuário pode ter
           * navegado para outra tela.
           */
          if (request.generation !=
              _generation) {
            continue;
          }

          if (_queue.isEmpty) {
            break;
          }

          /*
           * O pedido que estava na frente pode ter
           * sido retirado pela troca de geração.
           */
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

        /*
         * A tela pode ter mudado enquanto
         * aguardávamos a janela de performance.
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
         * antes de realmente iniciar o download.
         */
        _queue.removeFirst();

        final key =
            request.media.cacheKey;

        // --------------------------------------------------------
        // CACHE MAY HAVE BEEN FILLED WHILE WAITING
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

          /*
           * Mesmo que o usuário tenha mudado de
           * tela enquanto o arquivo estava sendo
           * baixado, o preview já existe fisicamente
           * e pode ser reutilizado posteriormente.
           */
          _memoryCache[key] =
              path;

          /*
           * Se a geração mudou durante o download,
           * aquela tela não precisa mais receber o
           * resultado.
           */
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

        /*
         * Espaçamento entre previews para não
         * disputar agressivamente CPU/rede/disco
         * com navegação e downloads grandes.
         */
        if (_queue.isNotEmpty) {
          await Future<void>.delayed(
            _betweenRequests,
          );
        }
      }
    } finally {
      _processing =
          false;

      /*
       * É possível que um novo pedido tenha
       * entrado exatamente enquanto o loop
       * estava terminando.
       */
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

      /*
       * Só seguramos previews quando:
       *
       * 1. existe um download grande rodando;
       * 2. o usuário está interagindo com a UI.
       */
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

    /*
     * Esta é a mudança mais importante.
     *
     * Antigamente pedidos antigos continuavam
     * ocupando a frente da List e precisavam ser
     * removidos um por um pelo loop principal.
     *
     * Agora são retirados imediatamente da fila
     * que atende a tela atual.
     */
    _moveQueuedRequestsToStaleQueue();

    _startStaleCancellation();

    /*
     * Caso o processador estivesse parado e
     * existam pedidos válidos, garante retomada.
     */
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

      /*
       * Remove imediatamente do mapa de in-flight
       * quando ainda for exatamente esta requisição.
       *
       * Assim uma nova tela pode pedir a mesma
       * imagem sem reutilizar o Future antigo.
       */
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

        /*
         * Mantemos o pequeno espaçamento que já
         * existia anteriormente, mas agora ele não
         * bloqueia a fila de previews da tela nova.
         */
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