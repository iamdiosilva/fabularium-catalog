import 'dart:async';

import '../models/telegram_media.dart';
import 'download_queue_service.dart';
import 'telegram_download_worker.dart';
import 'telegram_service_coordinator.dart';

class TelegramPreviewManager {
  TelegramPreviewManager._();

  static final TelegramPreviewManager instance =
      TelegramPreviewManager._();

  final TelegramDownloadWorker _worker =
      TelegramDownloadWorker.instance;

  final DownloadQueueService _downloadQueue =
      DownloadQueueService.instance;

  final TelegramPerformanceCoordinator
      _performance =
      TelegramPerformanceCoordinator.instance;

  final Map<String, String> _memoryCache =
      {};

  final Map<String, _InFlightPreview> _inFlight =
      {};

  final List<_PreviewRequest> _queue =
      [];

  bool _processing =
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

  String? cachedPath(
    TelegramMedia media,
  ) {
    return _memoryCache[
        media.cacheKey];
  }

  Future<String> getPreview(
    TelegramMedia media,
  ) {
    final key =
        media.cacheKey;

    final cached =
        _memoryCache[key];

    if (cached !=
        null) {
      return Future<String>.value(
        cached,
      );
    }

    final existing =
        _inFlight[key];

    /*
     * Reutilizamos somente uma requisição
     * pertencente à tela atual.
     */
    if (existing !=
            null &&
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

    _queue.add(
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

  void _startProcessing() {
    if (_processing) {
      return;
    }

    _processQueue();
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
         * Solicitação de uma página que já
         * não existe mais.
         *
         * Removemos UMA POR VEZ.
         *
         * Isso evita a tempestade de
         * completeError() durante Navigator.pop.
         */
        if (request.generation !=
            _generation) {
          _queue.removeAt(
            0,
          );

          _removeInFlightIfSame(
            request,
          );

          if (!request
              .completer
              .isCompleted) {
            request.completer.completeError(
              const TelegramPreviewCancelledException(),
            );
          }

          /*
           * Distribui os cancelamentos.
           */
          await Future<void>.delayed(
            const Duration(
              milliseconds:
                  8,
            ),
          );

          continue;
        }

        if (_needsInitialDelay) {
          _needsInitialDelay =
              false;

          await Future<void>.delayed(
            _initialDelay,
          );

          if (_queue.isEmpty) {
            break;
          }

          /*
           * Pode ter ocorrido troca de tela
           * durante o delay.
           */
          if (_queue.first.generation !=
              _generation) {
            continue;
          }
        }

        /*
         * O caso crítico que estávamos vendo:
         *
         * arquivo grande baixando
         * +
         * usuário abrindo grupos
         *
         * Nesse momento previews não possuem
         * prioridade.
         */
        await _waitForPerformanceWindow(
          request,
        );

        if (_queue.isEmpty) {
          break;
        }

        if (request.generation !=
            _generation) {
          continue;
        }

        /*
         * Remove somente no momento em que
         * realmente vamos executar.
         */
        _queue.removeAt(
          0,
        );

        final key =
            request.media.cacheKey;

        final cached =
            _memoryCache[key];

        if (cached !=
            null) {
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

        try {
          final path =
              await _worker
                  .downloadPreview(
            request.media,
          );

          _memoryCache[key] =
              path;

          if (!request
              .completer
              .isCompleted) {
            request.completer.complete(
              path,
            );
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
       * Apenas a combinação das duas coisas
       * pausa preview:
       *
       * download grande
       * +
       * navegação ativa
       *
       * Se o usuário parar de navegar por
       * ~1,4 s, os previews podem continuar.
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

  /*
   * Uma nova tela significa uma nova geração.
   *
   * Nada é cancelado imediatamente.
   */
  void prepareForScreen() {
    _generation++;

    _needsInitialDelay =
        true;

    _startProcessing();
  }

  /*
   * Chamado atualmente no dispose da página.
   *
   * Antes esse método disparava vários
   * completeError() síncronos.
   *
   * Agora apenas invalida a geração.
   */
  void cancelPending({
    bool resetInitialDelay = true,
  }) {
    _generation++;

    if (resetInitialDelay) {
      _needsInitialDelay =
          true;
    }

    _startProcessing();
  }

  void clearMemoryCache() {
    _memoryCache.clear();
  }
}

class _PreviewRequest {
  final TelegramMedia media;

  final Completer<String> completer;

  final int generation;

  final _InFlightPreview inFlight;

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