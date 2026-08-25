import 'dart:async';

import 'download_queue_service.dart';
import 'telegram_browse_worker.dart';
import 'telegram_download_worker.dart';
import 'telegram_preview_manager.dart';
import 'telegram_service.dart';

class TelegramSessionLifecycle {
  TelegramSessionLifecycle._() {
    /*
     * O callback é registrado no MAIN ISOLATE.
     *
     * Quando o BrowseWorker detectar que a
     * autorização foi revogada/expirada,
     * ele avisa este lifecycle.
     */
    _browseWorker.setSessionInvalidHandler(
      _handleBrowseSessionInvalid,
    );
  }

  static final TelegramSessionLifecycle instance =
      TelegramSessionLifecycle._();

  final TelegramBrowseWorker _browseWorker =
      TelegramBrowseWorker.instance;

  final TelegramDownloadWorker _downloadWorker =
      TelegramDownloadWorker.instance;

  final DownloadQueueService _downloadQueue =
      DownloadQueueService.instance;

  final TelegramPreviewManager _previewManager =
      TelegramPreviewManager.instance;

  final TelegramService _telegram =
      TelegramService.instance;

  Future<void>? _resetFuture;

  Future<void>? _invalidSessionFuture;

  // ============================================================
  // INVALID SESSION
  // ============================================================

  Future<void> _handleBrowseSessionInvalid(
    String errorMessage,
  ) {
    return invalidateSession(
      errorMessage,
    );
  }

  Future<void> invalidateSession(
    String errorMessage,
  ) {
    final existing =
        _invalidSessionFuture;

    if (existing != null) {
      return existing;
    }

    late final Future<void>
        future;

    future = _performInvalidSession(
      errorMessage,
    ).whenComplete(
      () {
        if (identical(
          _invalidSessionFuture,
          future,
        )) {
          _invalidSessionFuture =
              null;
        }
      },
    );

    _invalidSessionFuture =
        future;

    return future;
  }

  Future<void> _performInvalidSession(
    String errorMessage,
  ) async {
    /*
     * Primeiro atualizamos a sessão principal.
     *
     * Isso faz TelegramService.state mudar
     * imediatamente para disconnected e
     * notifica a TelegramLoginPage pelo
     * stateStream.
     *
     * TelegramService.logout() aqui NÃO envia
     * auth.logOut para o Telegram.
     *
     * Ele somente apaga nossa sessão local,
     * fecha eventual conexão local e atualiza
     * o estado do aplicativo.
     */
    try {
      await _telegram.logout();
    } catch (_) {
      /*
       * Mesmo se a limpeza local apresentar
       * algum problema, ainda precisamos
       * derrubar todos os workers.
       */
    }

    await resetForLogout(
      reason:
          TelegramSessionInvalidException(
        errorMessage,
      ),
    );
  }

  // ============================================================
  // SESSION RESET
  // ============================================================

  Future<void> resetForLogout({
    Object reason =
        const TelegramSessionResetException(),
  }) {
    final existing =
        _resetFuture;

    if (existing != null) {
      return existing;
    }

    late final Future<void>
        future;

    future = _performReset(
      reason:
          reason,
    ).whenComplete(
      () {
        if (identical(
          _resetFuture,
          future,
        )) {
          _resetFuture =
              null;
        }
      },
    );

    _resetFuture =
        future;

    return future;
  }

  Future<void> _performReset({
    required Object reason,
  }) async {
    /*
     * Invalida imediatamente previews da tela atual
     * e limpa somente o cache em memória.
     *
     * O cache físico e arquivos já baixados
     * continuam no disco.
     */
    _previewManager.cancelPending();

    _previewManager.clearMemoryCache();

    /*
     * Remove da fila tudo que não está efetivamente
     * executando.
     *
     * Isso impede o queue processor de iniciar
     * o próximo arquivo quando o download atual
     * for cancelado pelo reset do worker.
     */
    _removeNonRunningDownloadTasks();

    try {
      await _browseWorker.reset(
        reason:
            reason,
        clearCache:
            true,
      );
    } catch (_) {
      /*
       * best effort
       */
    }

    try {
      await _downloadWorker.resetSession();
    } catch (_) {
      /*
       * best effort
       */
    }

    /*
     * O Future do download ativo recebe erro quando
     * o worker é resetado.
     *
     * Cedemos alguns ciclos para
     * DownloadQueueService atualizar o task
     * para failed.
     */
    await Future<void>.delayed(
      Duration.zero,
    );

    await Future<void>.delayed(
      Duration.zero,
    );

    _removeNonRunningDownloadTasks();
  }

  void _removeNonRunningDownloadTasks() {
    final tasks =
        _downloadQueue.tasks.toList();

    for (final task
        in tasks) {
      if (task.isDownloading) {
        continue;
      }

      _downloadQueue.remove(
        task,
      );
    }
  }
}

class TelegramSessionResetException
    implements Exception {
  const TelegramSessionResetException();

  @override
  String toString() =>
      'Telegram session ended.';
}