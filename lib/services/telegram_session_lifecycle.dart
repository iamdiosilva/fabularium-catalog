import 'dart:async';

import 'download_queue_service.dart';
import 'telegram_browse_worker.dart';
import 'telegram_download_worker.dart';
import 'telegram_preview_manager.dart';
import 'telegram_service.dart';

class TelegramSessionLifecycle {
  TelegramSessionLifecycle._() {
    /*
     * Todos os workers reportam uma sessão
     * inválida para o MAIN ISOLATE.
     *
     * Independentemente de o erro aparecer
     * durante:
     *
     * - grupos;
     * - mensagens;
     * - download;
     * - preview.
     *
     * todos convergem para o mesmo fluxo
     * de encerramento da sessão.
     */
    _browseWorker.setSessionInvalidHandler(
      _handleSessionInvalid,
    );

    _downloadWorker.setSessionInvalidHandler(
      _handleSessionInvalid,
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

  Future<void> _handleSessionInvalid(
    String errorMessage,
  ) {
    return invalidateSession(
      errorMessage,
    );
  }

  Future<void> invalidateSession(
    String errorMessage,
  ) {
    /*
     * Browse, Download e Preview podem
     * perceber a mesma invalidação quase
     * simultaneamente.
     *
     * Este Future funciona como dedupe global.
     */
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
     * Primeiro atualizamos a sessão do
     * MAIN ISOLATE.
     *
     * TelegramService muda para disconnected
     * e notifica automaticamente qualquer
     * tela ouvindo stateStream.
     *
     * logout() aqui somente encerra nossa
     * sessão local. Não executa auth.logOut
     * remoto.
     */
    try {
      await _telegram.logout();
    } catch (_) {
      /*
       * Mesmo se houver problema apagando
       * a sessão local, os workers ainda
       * precisam ser encerrados.
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
     * Invalida imediatamente previews da tela
     * atual e limpa somente o cache em memória.
     *
     * Arquivos físicos e downloads já concluídos
     * permanecem no disco.
     */
    _previewManager.cancelPending();

    _previewManager.clearMemoryCache();

    /*
     * Remove tarefas que ainda não estão
     * efetivamente executando.
     *
     * Isso impede o queue processor de iniciar
     * outro arquivo enquanto encerramos a sessão.
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
     * O Future do download que estava executando
     * recebe erro quando o worker é resetado.
     *
     * Cedemos dois ciclos para
     * DownloadQueueService atualizar o estado
     * da tarefa antes da limpeza final.
     */
    await Future<void>.delayed(
      Duration.zero,
    );

    await Future<void>.delayed(
      Duration.zero,
    );

    _removeNonRunningDownloadTasks();
  }

  // ============================================================
  // DOWNLOAD QUEUE
  // ============================================================

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