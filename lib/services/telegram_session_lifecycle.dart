import 'dart:async';

import 'download_queue_service.dart';
import 'telegram_browse_worker.dart';
import 'telegram_download_worker.dart';
import 'telegram_preview_manager.dart';

class TelegramSessionLifecycle {
  TelegramSessionLifecycle._();

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

  Future<void>? _resetFuture;

  Future<void> resetForLogout() {
    final existing =
        _resetFuture;

    if (existing !=
        null) {
      return existing;
    }

    late final Future<void>
        future;

    future =
        _performReset().whenComplete(
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

  Future<void> _performReset() async {
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
     * executando. Isso impede o queue processor de
     * iniciar o próximo arquivo quando o download
     * atual for cancelado pelo reset do worker.
     */
    _removeNonRunningDownloadTasks();

    try {
      await _browseWorker.reset(
        reason:
            const TelegramSessionResetException(),
        clearCache:
            true,
      );
    } catch (_) {
      /* best effort */
    }

    try {
      await _downloadWorker.resetSession();
    } catch (_) {
      /* best effort */
    }

    /*
     * O Future do download ativo recebe erro quando
     * o worker é resetado. Cedemos alguns ciclos para
     * DownloadQueueService atualizar o task para failed.
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
