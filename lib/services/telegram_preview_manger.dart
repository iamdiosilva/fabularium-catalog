import 'dart:async';

import '../models/telegram_media.dart';
import 'telegram_download_worker.dart';

class TelegramPreviewManager {
  TelegramPreviewManager._();

  static final TelegramPreviewManager instance =
      TelegramPreviewManager._();

  final TelegramDownloadWorker _worker =
      TelegramDownloadWorker.instance;

  final Map<String, String> _memoryCache =
      {};

  final Map<String, Future<String>> _inFlight =
      {};

  final List<_PreviewRequest> _queue =
      [];

  bool _processing =
      false;

  bool _needsInitialDelay =
      true;

  static const Duration _betweenRequests =
      Duration(
    milliseconds: 120,
  );

  static const Duration _initialDelay =
      Duration(
    milliseconds: 400,
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

    if (cached != null) {
      return Future<String>.value(
        cached,
      );
    }

    final existing =
        _inFlight[key];

    if (existing != null) {
      return existing;
    }

    final completer =
        Completer<String>();

    final future =
        completer.future;

    _inFlight[key] =
        future;

    _queue.add(
      _PreviewRequest(
        media:
            media,
        completer:
            completer,
      ),
    );

    _startProcessing();

    return future;
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
        /*
         * O delay fica dentro do loop.
         *
         * Assim, se sairmos de uma tela e
         * entrarmos em outra enquanto existe
         * um preview anterior terminando,
         * o novo grupo ainda ganha um tempo
         * para desenhar antes dos previews.
         */
        if (_needsInitialDelay) {
          _needsInitialDelay =
              false;

          await Future<void>.delayed(
            _initialDelay,
          );

          /*
           * A página pode ter sido fechada
           * durante o delay.
           */
          if (_queue.isEmpty) {
            break;
          }
        }

        final request =
            _queue.removeAt(
          0,
        );

        final key =
            request.media.cacheKey;

        final cached =
            _memoryCache[key];

        if (cached != null) {
          if (!request
              .completer
              .isCompleted) {
            request.completer.complete(
              cached,
            );
          }

          _inFlight.remove(
            key,
          );

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
            request
                .completer
                .completeError(
              error,
              stackTrace,
            );
          }
        } finally {
          _inFlight.remove(
            key,
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

  /*
   * Chamar sempre que uma nova tela
   * de mensagens for aberta.
   *
   * Isso também descarta previews pendentes
   * deixados pela tela anterior.
   */
  void prepareForScreen() {
    cancelPending(
      resetInitialDelay:
          false,
    );

    _needsInitialDelay =
        true;
  }

  /*
   * Cancela apenas os itens que ainda não
   * começaram.
   *
   * O preview que já está sendo processado
   * pode terminar normalmente.
   *
   * Resultado:
   *
   * ao fechar um grupo com 10 previews
   * pendentes, não continuamos baixando
   * os 10 depois que a tela desapareceu.
   */
  void cancelPending({
    bool resetInitialDelay = true,
  }) {
    if (_queue.isEmpty) {
      if (resetInitialDelay) {
        _needsInitialDelay =
            true;
      }

      return;
    }

    final pendingRequests =
        List<_PreviewRequest>.from(
      _queue,
    );

    _queue.clear();

    for (final request
        in pendingRequests) {
      final key =
          request.media.cacheKey;

      _inFlight.remove(
        key,
      );

      if (!request
          .completer
          .isCompleted) {
        request.completer.completeError(
          const TelegramPreviewCancelledException(),
        );
      }
    }

    if (resetInitialDelay) {
      _needsInitialDelay =
          true;
    }
  }

  void clearMemoryCache() {
    _memoryCache.clear();
  }
}

class _PreviewRequest {
  final TelegramMedia media;

  final Completer<String>
      completer;

  const _PreviewRequest({
    required this.media,
    required this.completer,
  });
}

class TelegramPreviewCancelledException
    implements Exception {
  const TelegramPreviewCancelledException();

  @override
  String toString() =>
      'Preview cancelled.';
}