import 'package:flutter/material.dart';

import '../models/download_task.dart';
import '../services/download_queue_service.dart';

class DownloadQueuePage extends StatelessWidget {
  const DownloadQueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = DownloadQueueService.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          AnimatedBuilder(
            animation: queue,
            builder: (context, child) {
              if (queue.completedTasks.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Clear Completed',
                onPressed: queue.clearCompleted,
                icon: const Icon(Icons.cleaning_services_outlined),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: queue,
        builder: (context, child) {
          final tasks = queue.tasks;
          if (tasks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_done_outlined, size: 72),
                  SizedBox(height: 16),
                  Text('No downloads yet.'),
                ],
              ),
            );
          }
          return Column(
            children: [
              _DownloadSummary(queue: queue),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: tasks.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return ValueListenableBuilder<int>(
                      valueListenable: queue.listenableForMedia(task.media, task.groupTitle),
                      builder: (context, revision, child) => _DownloadTaskCard(task: task, queue: queue),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DownloadSummary extends StatelessWidget {
  final DownloadQueueService queue;
  const _DownloadSummary({required this.queue});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: queue.progressListenable,
      builder: (context, revision, child) {
        final current = queue.currentTask;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Wrap(
            spacing: 24,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _SummaryItem(icon: Icons.downloading, label: 'Active', value: queue.activeCount),
              _SummaryItem(icon: Icons.schedule, label: 'Queued', value: queue.queuedCount),
              _SummaryItem(icon: Icons.check_circle_outline, label: 'Completed', value: queue.completedCount),
              if (queue.failedCount > 0)
                _SummaryItem(icon: Icons.error_outline, label: 'Failed', value: queue.failedCount),
              if (current != null && current.bytesPerSecond > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.speed, size: 18),
                    const SizedBox(width: 6),
                    Text('${_formatSize(current.bytesPerSecond.round())}/s'),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  static String _formatSize(int bytes) {
    const kb = 1024, mb = kb * 1024, gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}

class _SummaryItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  const _SummaryItem({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 6), Text('$label: $value')],
      );
}

class _DownloadTaskCard extends StatelessWidget {
  final DownloadTask task;
  final DownloadQueueService queue;
  const _DownloadTaskCard({required this.task, required this.queue});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(child: Icon(_statusIcon())),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.media.fileName, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(task.groupTitle, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text(_statusText(), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                _buildActions(),
              ],
            ),
            if (task.isQueued || task.isDownloading) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(value: task.isQueued ? 0 : task.progress),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(task.isQueued ? 'Waiting in queue...' : _progressText(),
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  Text(_formatSize(task.totalBytes), style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              if (task.isDownloading && task.bytesPerSecond > 0) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.speed, size: 16),
                    const SizedBox(width: 6),
                    Text('${_formatSize(task.bytesPerSecond.round())}/s'),
                    if (task.estimatedRemaining != null && task.estimatedRemaining!.inSeconds > 0) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.timer_outlined, size: 16),
                      const SizedBox(width: 6),
                      Text(_formatDuration(task.estimatedRemaining!)),
                    ],
                  ],
                ),
              ],
            ],
            if (task.isFailed && task.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(task.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    if (task.isCompleted) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'Show in Folder', onPressed: () => queue.showInFolder(task), icon: const Icon(Icons.folder_open)),
        IconButton(tooltip: 'Remove', onPressed: () => queue.remove(task), icon: const Icon(Icons.close)),
      ]);
    }
    if (task.isFailed) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'Retry', onPressed: () => queue.retry(task), icon: const Icon(Icons.refresh)),
        IconButton(tooltip: 'Remove', onPressed: () => queue.remove(task), icon: const Icon(Icons.close)),
      ]);
    }
    if (task.isQueued) {
      return IconButton(tooltip: 'Remove from Queue', onPressed: () => queue.remove(task), icon: const Icon(Icons.close));
    }
    return const SizedBox.shrink();
  }

  IconData _statusIcon() {
    if (task.isDownloading) return Icons.downloading;
    if (task.isCompleted) return Icons.check_circle_outline;
    if (task.isFailed) return Icons.error_outline;
    return Icons.schedule;
  }

  String _statusText() {
    if (task.isQueued) return 'Queued';
    if (task.isDownloading) return 'Downloading';
    if (task.isCompleted) return 'Completed';
    return 'Failed';
  }

  String _progressText() {
    final progress = task.progress;
    if (progress == null) return _formatSize(task.receivedBytes);
    return '${(progress * 100).toStringAsFixed(0)}% • ${_formatSize(task.receivedBytes)}';
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) return '~${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    if (duration.inMinutes > 0) return '~${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    return '~${duration.inSeconds}s';
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return 'Unknown';
    const kb = 1024, mb = kb * 1024, gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}
