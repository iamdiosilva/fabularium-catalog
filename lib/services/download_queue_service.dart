import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/download_task.dart';
import '../models/telegram_media.dart';
import 'telegram_download_engine.dart';
import 'telegram_service.dart';

class DownloadQueueService
    extends ChangeNotifier {
  DownloadQueueService._();

  static final DownloadQueueService instance =
      DownloadQueueService._();

  final TelegramService _telegram =
      TelegramService.instance;

  final TelegramDownloadEngine
      _downloadEngine =
      TelegramDownloadEngine.instance;

  final List<DownloadTask> _tasks =
      [];

  bool _processing =
      false;

  /*
   * ============================================================
   * UI THROTTLING
   * ============================================================
   *
   * O downloader pode receber dezenas ou até
   * centenas de eventos de progresso por segundo.
   *
   * Não precisamos reconstruir a UI em cada um.
   *
   * Mantemos os valores internos atualizados em
   * tempo real, mas notificamos o Flutter no
   * máximo aproximadamente 6~7 vezes por segundo.
   */
  static const Duration _uiUpdateInterval =
      Duration(
    milliseconds: 150,
  );

  Timer? _progressUiTimer;

  DateTime _lastUiNotification =
      DateTime.fromMillisecondsSinceEpoch(
    0,
  );

  List<DownloadTask> get tasks =>
      List.unmodifiable(
        _tasks,
      );

  List<DownloadTask> get activeTasks =>
      _tasks
          .where(
            (task) =>
                task.isQueued ||
                task.isDownloading,
          )
          .toList();

  List<DownloadTask> get completedTasks =>
      _tasks
          .where(
            (task) =>
                task.isCompleted,
          )
          .toList();

  List<DownloadTask> get failedTasks =>
      _tasks
          .where(
            (task) =>
                task.isFailed,
          )
          .toList();

  DownloadTask? get currentTask {
    for (final task in _tasks) {
      if (task.isDownloading) {
        return task;
      }
    }

    return null;
  }

  int get activeCount =>
      activeTasks.length;

  int get queuedCount =>
      _tasks
          .where(
            (task) =>
                task.isQueued,
          )
          .length;

  int get completedCount =>
      completedTasks.length;

  int get failedCount =>
      failedTasks.length;

  bool get hasTasks =>
      _tasks.isNotEmpty;

  bool get hasActiveDownloads =>
      activeCount > 0;

  String buildTaskId(
    TelegramMedia media,
    String groupTitle,
  ) {
    return '$groupTitle|'
        '${media.cacheKey}|'
        '${media.fileName}';
  }

  DownloadTask? taskForMedia(
    TelegramMedia media,
    String groupTitle,
  ) {
    final id =
        buildTaskId(
      media,
      groupTitle,
    );

    for (final task in _tasks) {
      if (task.id ==
          id) {
        return task;
      }
    }

    return null;
  }

  DownloadTask enqueue({
    required TelegramMedia media,
    required String groupTitle,
  }) {
    final existing =
        taskForMedia(
      media,
      groupTitle,
    );

    if (existing != null) {
      if (existing.isFailed) {
        retry(
          existing,
        );
      }

      return existing;
    }

    final downloadedPath =
        _telegram
            .getDownloadedMediaPath(
      media,
      groupTitle:
          groupTitle,
    );

    final task =
        DownloadTask(
      id:
          buildTaskId(
        media,
        groupTitle,
      ),
      media:
          media,
      groupTitle:
          groupTitle,
      createdAt:
          DateTime.now(),
      status:
          downloadedPath != null
              ? DownloadTaskStatus.completed
              : DownloadTaskStatus.queued,
      receivedBytes:
          downloadedPath != null
              ? media.size
              : 0,
      totalBytes:
          media.size,
      filePath:
          downloadedPath,
    );

    _tasks.insert(
      0,
      task,
    );

    _notifyImmediately();

    if (task.isQueued) {
      _startProcessing();
    }

    return task;
  }

  void retry(
    DownloadTask task,
  ) {
    if (task.isDownloading) {
      return;
    }

    task.status =
        DownloadTaskStatus.queued;

    task.receivedBytes =
        0;

    task.totalBytes =
        task.media.size;

    task.errorMessage =
        null;

    task.filePath =
        null;

    task.startedAt =
        null;

    task.completedAt =
        null;

    task.bytesPerSecond =
        0;

    task.estimatedRemaining =
        null;

    _notifyImmediately();

    _startProcessing();
  }

  void remove(
    DownloadTask task,
  ) {
    if (task.isDownloading) {
      return;
    }

    _tasks.remove(
      task,
    );

    _notifyImmediately();
  }

  void clearCompleted() {
    _tasks.removeWhere(
      (task) =>
          task.isCompleted,
    );

    _notifyImmediately();
  }

  void clearFinished() {
    _tasks.removeWhere(
      (task) =>
          task.isFinished,
    );

    _notifyImmediately();
  }

  Future<void> showInFolder(
    DownloadTask task,
  ) async {
    final path =
        task.filePath;

    if (path == null) {
      return;
    }

    await _telegram
        .showFileInExplorer(
      path,
    );
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
      while (true) {
        DownloadTask?
            nextTask;

        /*
         * Mantemos FIFO.
         */
        for (final task
            in _tasks.reversed) {
          if (task.isQueued) {
            nextTask =
                task;

            break;
          }
        }

        if (nextTask ==
            null) {
          break;
        }

        await _executeTask(
          nextTask,
        );
      }
    } finally {
      _processing =
          false;

      _notifyImmediately();
    }
  }

  Future<void> _executeTask(
    DownloadTask task,
  ) async {
    task.status =
        DownloadTaskStatus.downloading;

    task.errorMessage =
        null;

    task.receivedBytes =
        0;

    task.totalBytes =
        task.media.size;

    task.startedAt =
        DateTime.now();

    task.completedAt =
        null;

    task.bytesPerSecond =
        0;

    task.estimatedRemaining =
        null;

    /*
     * Mudança de status deve aparecer
     * imediatamente.
     */
    _notifyImmediately();

    DateTime lastSampleTime =
        DateTime.now();

    int lastSampleBytes =
        0;

    try {
      final path =
          await _downloadEngine
              .downloadMedia(
        task.media,
        groupTitle:
            task.groupTitle,
        onProgress:
            (
          received,
          total,
        ) {
          /*
           * Esses valores continuam sendo
           * atualizados para cada chunk.
           *
           * Só não reconstruímos a UI
           * imediatamente.
           */
          task.receivedBytes =
              received;

          if (total > 0) {
            task.totalBytes =
                total;
          }

          final now =
              DateTime.now();

          final elapsedMilliseconds =
              now
                  .difference(
                    lastSampleTime,
                  )
                  .inMilliseconds;

          /*
           * Velocidade e ETA precisam de
           * atualização ainda mais lenta.
           */
          if (elapsedMilliseconds >=
                  400 ||
              (total > 0 &&
                  received >=
                      total)) {
            final deltaBytes =
                received -
                    lastSampleBytes;

            final seconds =
                elapsedMilliseconds /
                    1000.0;

            if (seconds > 0 &&
                deltaBytes >= 0) {
              final instantSpeed =
                  deltaBytes /
                      seconds;

              /*
               * Média suavizada.
               */
              if (task.bytesPerSecond <=
                  0) {
                task.bytesPerSecond =
                    instantSpeed;
              } else {
                task.bytesPerSecond =
                    (task.bytesPerSecond *
                            0.65) +
                        (instantSpeed *
                            0.35);
              }

              /*
               * ETA.
               */
              if (task.totalBytes > 0 &&
                  task.bytesPerSecond >
                      0) {
                final remainingBytes =
                    task.totalBytes -
                        received;

                if (remainingBytes >
                    0) {
                  final remainingSeconds =
                      remainingBytes /
                          task
                              .bytesPerSecond;

                  task.estimatedRemaining =
                      Duration(
                    seconds:
                        remainingSeconds
                            .ceil(),
                  );
                } else {
                  task.estimatedRemaining =
                      Duration.zero;
                }
              }
            }

            lastSampleBytes =
                received;

            lastSampleTime =
                now;
          }

          /*
           * IMPORTANTE:
           *
           * Antes:
           *
           * notifyListeners();
           *
           * Agora:
           *
           * agenda uma atualização visual
           * controlada.
           */
          _scheduleProgressNotification();
        },
      );

      task.filePath =
          path;

      if (task.totalBytes >
          0) {
        task.receivedBytes =
            task.totalBytes;
      }

      task.status =
          DownloadTaskStatus.completed;

      task.completedAt =
          DateTime.now();

      task.estimatedRemaining =
          Duration.zero;

      task.errorMessage =
          null;
    } catch (e) {
      task.status =
          DownloadTaskStatus.failed;

      task.errorMessage =
          e.toString();

      task.completedAt =
          DateTime.now();

      task.estimatedRemaining =
          null;
    }

    /*
     * Conclusão ou erro aparece imediatamente.
     */
    _notifyImmediately();
  }

  // ============================================================
  // UI NOTIFICATION
  // ============================================================

  void _scheduleProgressNotification() {
    final now =
        DateTime.now();

    final elapsed =
        now.difference(
      _lastUiNotification,
    );

    /*
     * Já passou o intervalo mínimo.
     *
     * Podemos atualizar imediatamente.
     */
    if (elapsed >=
        _uiUpdateInterval) {
      _notifyImmediately();

      return;
    }

    /*
     * Já existe uma atualização agendada.
     *
     * Não criamos outro Timer.
     */
    if (_progressUiTimer !=
        null) {
      return;
    }

    final remaining =
        _uiUpdateInterval -
            elapsed;

    _progressUiTimer =
        Timer(
      remaining,
      () {
        _progressUiTimer =
            null;

        _lastUiNotification =
            DateTime.now();

        notifyListeners();
      },
    );
  }

  void _notifyImmediately() {
    /*
     * Cancela atualização atrasada,
     * pois vamos atualizar agora.
     */
    _progressUiTimer?.cancel();

    _progressUiTimer =
        null;

    _lastUiNotification =
        DateTime.now();

    notifyListeners();
  }

  @override
  void dispose() {
    _progressUiTimer?.cancel();

    _progressUiTimer =
        null;

    super.dispose();
  }
}