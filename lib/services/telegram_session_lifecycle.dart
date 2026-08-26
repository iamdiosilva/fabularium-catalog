import 'dart:async';

import 'download_queue_service.dart';
import 'telegram_browse_worker.dart';
import 'telegram_download_worker.dart';
import 'telegram_preview_manager.dart';
import 'telegram_service.dart';

class TelegramSessionLifecycle {
  TelegramSessionLifecycle._() {
    /*
     * Todos os workers convergem para o mesmo
     * fluxo de invalidação no MAIN ISOLATE.
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

  /*
   * Ainda mantemos a referência porque este
   * lifecycle registra o callback de sessão
   * inválida do Download/Preview Worker.
   *
   * O reset operacional dele agora pertence
   * ao DownloadQueueService.
   */
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
     * Browse, Download e Preview podem perceber
     * a mesma invalidação simultaneamente.
     *
     * Este Future faz o dedupe global.
     */
    final existing =
        _invalidSessionFuture;

    if (existing != null) {
      return existing;
    }

    late final Future<void> future;

    future =
        _performInvalidSession(
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
     * Atualiza primeiro o estado do
     * TelegramService no MAIN ISOLATE.
     */
    try {
      await _telegram.logout();
    } catch (_) {
      /*
       * Os workers ainda precisam ser
       * encerrados mesmo se a limpeza
       * da sessão local falhar.
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

    late final Future<void> future;

    future =
        _performReset(
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
     * Cancela previews pertencentes à sessão
     * atual e limpa somente o cache em memória.
     *
     * O cache físico permanece intacto e continua
     * sendo administrado pelo limite de tamanho/
     * idade do TelegramFileService.
     */
    _previewManager.cancelPending();

    _previewManager.clearMemoryCache();

    /*
     * Browse é responsabilidade direta
     * do lifecycle.
     */
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

    /*
     * A fila agora controla integralmente:
     *
     * - tarefas queued;
     * - tarefa downloading;
     * - reset do Download/Preview Worker;
     * - limpeza das tarefas da sessão anterior.
     */
    try {
      await _downloadQueue
          .resetForSessionEnd();
    } catch (_) {
      /*
       * best effort
       */
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

class TelegramSessionInvalidException implements Exception {
  final String message;

  const TelegramSessionInvalidException(this.message);

  @override
  String toString() => message;
}
