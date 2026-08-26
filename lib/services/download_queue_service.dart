import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/download_task.dart';
import '../models/telegram_media.dart';
import 'telegram_download_worker.dart';
import 'telegram_file_service.dart';

class DownloadQueueService
    extends ChangeNotifier {
  DownloadQueueService._();

  static final DownloadQueueService instance =
      DownloadQueueService._();

  final TelegramFileService _files =
      TelegramFileService.instance;

  final TelegramDownloadWorker _downloadWorker =
      TelegramDownloadWorker.instance;

  final List<DownloadTask> _tasks =
      [];

  final Map<String, DownloadTask> _tasksById =
      {};

  final Map<String, ValueNotifier<int>>
      _taskRevisions =
      {};

  final ValueNotifier<int> _progressRevision =
      ValueNotifier<int>(
    0,
  );

  ValueListenable<int> get progressListenable =>
      _progressRevision;

  bool _processing =
      false;

  bool _sessionResetting =
      false;

  Future<void>? _sessionResetFuture;

  static const Duration _uiUpdateInterval =
      Duration(
    milliseconds: 150,
  );

  Timer? _progressUiTimer;

  DateTime _lastUiNotification =
      DateTime.fromMillisecondsSinceEpoch(
    0,
  );

  final Set<String> _pendingTaskNotifications =
      {};

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  List<DownloadTask> get activeTasks => _tasks
      .where((task) => task.isQueued || task.isDownloading)
      .toList();

  List<DownloadTask> get completedTasks =>
      _tasks.where((task) => task.isCompleted).toList();

  List<DownloadTask> get failedTasks =>
      _tasks.where((task) => task.isFailed).toList();

  DownloadTask? get currentTask {
    for (final task in _tasks) {
      if (task.isDownloading) return task;
    }
    return null;
  }

  int get activeCount => _tasks.where((t) => t.isQueued || t.isDownloading).length;
  int get queuedCount => _tasks.where((t) => t.isQueued).length;
  int get completedCount => _tasks.where((t) => t.isCompleted).length;
  int get failedCount => _tasks.where((t) => t.isFailed).length;
  bool get hasTasks => _tasks.isNotEmpty;
  bool get hasActiveDownloads => activeCount > 0;

  String buildTaskId(TelegramMedia media, String groupTitle) =>
      '$groupTitle|${media.cacheKey}|${media.fileName}';

  DownloadTask? taskForMedia(TelegramMedia media, String groupTitle) =>
      _tasksById[buildTaskId(media, groupTitle)];

  ValueListenable<int> listenableForMedia(
    TelegramMedia media,
    String groupTitle,
  ) {
    final id = buildTaskId(media, groupTitle);
    return _taskRevisions.putIfAbsent(id, () => ValueNotifier<int>(0));
  }

  DownloadTask enqueue({
    required TelegramMedia media,
    required String groupTitle,
  }) {
    final id = buildTaskId(media, groupTitle);
    final existing = _tasksById[id];
    if (existing != null) {
      if (existing.isFailed && !_sessionResetting) retry(existing);
      return existing;
    }

    final downloadedPath = _files.getDownloadedMediaPath(
      media,
      groupTitle: groupTitle,
    );
    final task = DownloadTask(
      id: id,
      media: media,
      groupTitle: groupTitle,
      createdAt: DateTime.now(),
      status: downloadedPath != null
          ? DownloadTaskStatus.completed
          : DownloadTaskStatus.queued,
      receivedBytes: downloadedPath != null ? media.size : 0,
      totalBytes: media.size,
      filePath: downloadedPath,
    );
    _tasks.insert(0, task);
    _tasksById[id] = task;
    _notifyImmediately(task);
    if (task.isQueued && !_sessionResetting) _startProcessing();
    return task;
  }

  void retry(DownloadTask task) {
    if (task.isDownloading || _sessionResetting) return;
    task.status = DownloadTaskStatus.queued;
    task.receivedBytes = 0;
    task.totalBytes = task.media.size;
    task.errorMessage = null;
    task.filePath = null;
    task.startedAt = null;
    task.completedAt = null;
    task.bytesPerSecond = 0;
    task.estimatedRemaining = null;
    _notifyImmediately(task);
    _startProcessing();
  }

  void remove(DownloadTask task) {
    if (task.isDownloading) return;
    _tasks.remove(task);
    _tasksById.remove(task.id);
    _notifyImmediately(task);
  }

  void clearCompleted() {
    final removed = _tasks.where((task) => task.isCompleted).toList();
    _tasks.removeWhere((task) => task.isCompleted);
    for (final task in removed) {
      _tasksById.remove(task.id);
      _touchTask(task.id);
    }
    _notifyStructure();
  }

  void clearFinished() {
    final removed = _tasks.where((task) => task.isFinished).toList();
    _tasks.removeWhere((task) => task.isFinished);
    for (final task in removed) {
      _tasksById.remove(task.id);
      _touchTask(task.id);
    }
    _notifyStructure();
  }

  Future<void> resetForSessionEnd() {
    final existing = _sessionResetFuture;
    if (existing != null) return existing;
    late final Future<void> future;
    future = _performSessionReset().whenComplete(() {
      if (identical(_sessionResetFuture, future)) _sessionResetFuture = null;
    });
    _sessionResetFuture = future;
    return future;
  }

  Future<void> _performSessionReset() async {
    _sessionResetting = true;
    try {
      _removeNonRunningTasks();
      try {
        await _downloadWorker.resetSession();
      } catch (_) {}
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      _removeNonRunningTasks();
      _progressUiTimer?.cancel();
      _progressUiTimer = null;
      _pendingTaskNotifications.clear();
      _notifyStructure();
    } finally {
      _sessionResetting = false;
    }
  }

  void _removeNonRunningTasks() {
    final removed = _tasks.where((task) => !task.isDownloading).toList();
    if (removed.isEmpty) return;
    _tasks.removeWhere((task) => !task.isDownloading);
    for (final task in removed) {
      _tasksById.remove(task.id);
      _pendingTaskNotifications.remove(task.id);
      _touchTask(task.id);
    }
    _notifyStructure();
  }

  Future<void> showInFolder(DownloadTask task) async {
    final path = task.filePath;
    if (path == null) return;
    await _files.showFileInExplorer(path);
  }

  void _startProcessing() {
    if (_processing || _sessionResetting) return;
    unawaited(_processQueue());
  }

  Future<void> _processQueue() async {
    if (_processing || _sessionResetting) return;
    _processing = true;
    try {
      while (!_sessionResetting) {
        DownloadTask? nextTask;
        for (final task in _tasks.reversed) {
          if (task.isQueued) {
            nextTask = task;
            break;
          }
        }
        if (nextTask == null) break;
        await _executeTask(nextTask);
      }
    } finally {
      _processing = false;
      _notifyStructure();
      if (!_sessionResetting && queuedCount > 0) _startProcessing();
    }
  }

  Future<void> _executeTask(DownloadTask task) async {
    if (_sessionResetting) return;
    task.status = DownloadTaskStatus.downloading;
    task.errorMessage = null;
    task.receivedBytes = 0;
    task.totalBytes = task.media.size;
    task.startedAt = DateTime.now();
    task.completedAt = null;
    task.bytesPerSecond = 0;
    task.estimatedRemaining = null;
    _notifyImmediately(task);

    DateTime lastSampleTime = DateTime.now();
    int lastSampleBytes = 0;
    try {
      final path = await _downloadWorker.downloadMedia(
        task.media,
        groupTitle: task.groupTitle,
        onProgress: (received, total) {
          task.receivedBytes = received;
          if (total > 0) task.totalBytes = total;
          final now = DateTime.now();
          final elapsedMilliseconds = now.difference(lastSampleTime).inMilliseconds;
          if (elapsedMilliseconds >= 400 || (total > 0 && received >= total)) {
            final deltaBytes = received - lastSampleBytes;
            final seconds = elapsedMilliseconds / 1000.0;
            if (seconds > 0 && deltaBytes >= 0) {
              final instantSpeed = deltaBytes / seconds;
              if (task.bytesPerSecond <= 0) {
                task.bytesPerSecond = instantSpeed;
              } else {
                task.bytesPerSecond =
                    (task.bytesPerSecond * 0.65) + (instantSpeed * 0.35);
              }
              if (task.totalBytes > 0 && task.bytesPerSecond > 0) {
                final remainingBytes = task.totalBytes - received;
                task.estimatedRemaining = remainingBytes > 0
                    ? Duration(seconds: (remainingBytes / task.bytesPerSecond).ceil())
                    : Duration.zero;
              }
            }
            lastSampleBytes = received;
            lastSampleTime = now;
          }
          _scheduleProgressNotification(task);
        },
      );
      task.filePath = path;
      if (task.totalBytes > 0) task.receivedBytes = task.totalBytes;
      task.status = DownloadTaskStatus.completed;
      task.completedAt = DateTime.now();
      task.estimatedRemaining = Duration.zero;
      task.errorMessage = null;
    } catch (e) {
      task.status = DownloadTaskStatus.failed;
      task.errorMessage = e.toString();
      task.completedAt = DateTime.now();
      task.estimatedRemaining = null;
    }
    _notifyImmediately(task);
  }

  void _scheduleProgressNotification(DownloadTask task) {
    _pendingTaskNotifications.add(task.id);
    final now = DateTime.now();
    final elapsed = now.difference(_lastUiNotification);
    if (elapsed >= _uiUpdateInterval) {
      _flushProgressNotifications();
      return;
    }
    if (_progressUiTimer != null) return;
    _progressUiTimer = Timer(_uiUpdateInterval - elapsed, _flushProgressNotifications);
  }

  void _flushProgressNotifications() {
    _progressUiTimer?.cancel();
    _progressUiTimer = null;
    _lastUiNotification = DateTime.now();
    for (final id in _pendingTaskNotifications) {
      _touchTask(id);
    }
    _pendingTaskNotifications.clear();
    _progressRevision.value++;
  }

  void _notifyImmediately(DownloadTask task) {
    _progressUiTimer?.cancel();
    _progressUiTimer = null;
    _pendingTaskNotifications.remove(task.id);
    _lastUiNotification = DateTime.now();
    _touchTask(task.id);
    _progressRevision.value++;
    notifyListeners();
  }

  void _notifyStructure() {
    _progressRevision.value++;
    notifyListeners();
  }

  void _touchTask(String id) {
    final notifier = _taskRevisions[id];
    if (notifier == null) return;
    notifier.value++;
  }

  @override
  void dispose() {
    _progressUiTimer?.cancel();
    for (final notifier in _taskRevisions.values) {
      notifier.dispose();
    }
    _taskRevisions.clear();
    _progressRevision.dispose();
    super.dispose();
  }
}
