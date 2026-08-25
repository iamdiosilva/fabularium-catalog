import 'dart:async';

import '../models/telegram_media.dart';
import 'telegram_download_worker.dart';

class TelegramPreviewManager {
  TelegramPreviewManager._();

  static final TelegramPreviewManager instance =
      TelegramPreviewManager._();

  final TelegramDownloadWorker _worker =
      TelegramDownloadWorker.instance;

  /*
   * Preview que já foi obtido durante
   * esta execução do aplicativo.
   *
   * key = TelegramMedia.cacheKey
   */
  final Map<String, String> _memoryCache = {};

  /*
   * Evita isto:
   *
   * card antigo pede preview A
   * card novo pede preview A
   * outro card pede preview A
   *
   * e termos 3 downloads iguais.
   *
   * Todos recebem o MESMO Future.
   */
  final Map<String, Future<String>> _inFlight = {};

  final List<_PreviewRequest> _queue = [];

  bool _processing = false;

  /*
   * Pequeno atraso entre previews.
   *
   * Isso evita:
   *
   * preview termina
   * decode
   * setState
   * preview termina
   * decode
   * setState
   *
   * tudo dentro do mesmo pequeno intervalo.
   */
  static const Duration _betweenRequests =
      Duration(
    milliseconds: 100,
  );

  /*
   * Quando entramos no Telegram esperamos
   * um pouco antes de começar o primeiro
   * preview.
   *
   * Assim a tela consegue desenhar seus
   * primeiros frames sem competir com
   * inicialização de imagens.
   */
  static const Duration _initialDelay =
      Duration(
    milliseconds: 350,
  );

  bool _needsInitialDelay = true;

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

    /*
     * Já temos em memória.
     */
    final cached =
        _memoryCache[
            key];

    if (cached != null) {
      return Future<String>.value(
        cached,
      );
    }

    /*
     * Já existe uma solicitação desse
     * mesmo preview.
     *
     * Reutilizamos o Future.
     */
    final existing =
        _inFlight[
            key];

    if (existing != null) {
      return existing;
    }

    final completer =
        Completer<String>();

    final future =
        completer.future;

    _inFlight[
            key] =
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
      if (_needsInitialDelay) {
        _needsInitialDelay =
            false;

        await Future<void>.delayed(
          _initialDelay,
        );
      }

      while (_queue.isNotEmpty) {
        final request =
            _queue.removeAt(
          0,
        );

        final key =
            request.media.cacheKey;

        /*
         * Pode ter entrado no cache enquanto
         * aguardava na fila.
         */
        final cached =
            _memoryCache[
                key];

        if (cached != null) {
          if (!request
              .completer
              .isCompleted) {
            request
                .completer
                .complete(
              cached,
            );
          }

          _inFlight.remove(
            key,
          );

          continue;
        }

        try {
          /*
           * Toda comunicação Telegram
           * permanece fora do isolate da UI.
           */
          final path =
              await _worker
                  .downloadPreview(
            request.media,
          );

          _memoryCache[
                  key] =
              path;

          if (!request
              .completer
              .isCompleted) {
            request
                .completer
                .complete(
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

        /*
         * Distribui as atualizações visuais
         * no tempo.
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
       * Segurança para uma solicitação que
       * tenha entrado exatamente enquanto
       * finalizávamos.
       */
      if (_queue.isNotEmpty) {
        _startProcessing();
      }
    }
  }

  /*
   * Podemos chamar ao entrar novamente em
   * uma tela de Telegram.
   *
   * Não apagamos o cache.
   *
   * Apenas fazemos o próximo conjunto
   * aguardar um pouco antes de começar.
   */
  void prepareForScreen() {
    if (!_processing &&
        _queue.isEmpty) {
      _needsInitialDelay =
          true;
    }
  }

  /*
   * Útil posteriormente caso queiramos
   * limpar manualmente o cache em memória.
   *
   * Os arquivos físicos continuam no
   * cache do Telegram.
   */
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