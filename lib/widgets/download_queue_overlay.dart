import 'package:flutter/material.dart';

import '../models/download_task.dart';
import '../services/download_queue_service.dart';

class DownloadQueueOverlay
    extends StatelessWidget {
  final VoidCallback onOpen;

  const DownloadQueueOverlay({
    super.key,
    required this.onOpen,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final queue =
        DownloadQueueService.instance;

    return ValueListenableBuilder<int>(
      valueListenable:
          queue.progressListenable,
      builder:
          (
        context,
        revision,
        child,
      ) {
        if (!queue.hasTasks) {
          return const SizedBox
              .shrink();
        }

        final current =
            queue.currentTask;

        return Positioned(
          right:
              24,
          bottom:
              24,
          child:
              Material(
            elevation:
                8,
            borderRadius:
                BorderRadius.circular(
              14,
            ),
            color:
                Theme.of(context)
                    .colorScheme
                    .surface,
            child:
                InkWell(
              borderRadius:
                  BorderRadius.circular(
                14,
              ),
              onTap:
                  onOpen,
              child:
                  Container(
                width:
                    370,
                padding:
                    const EdgeInsets.all(
                  14,
                ),
                child:
                    current !=
                            null
                        ? _buildCurrent(
                            context,
                            queue,
                            current,
                          )
                        : _buildIdle(
                            context,
                            queue,
                          ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCurrent(
    BuildContext context,
    DownloadQueueService queue,
    DownloadTask task,
  ) {
    return Column(
      mainAxisSize:
          MainAxisSize.min,
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.downloading,
              size:
                  20,
            ),

            const SizedBox(
              width:
                  8,
            ),

            const Expanded(
              child:
                  Text(
                'Downloading',
                style:
                    TextStyle(
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),

            if (queue.queuedCount >
                0)
              Text(
                '+${queue.queuedCount} queued',
                style:
                    Theme.of(context)
                        .textTheme
                        .bodySmall,
              ),
          ],
        ),

        const SizedBox(
          height:
              10,
        ),

        Text(
          task.media.fileName,
          maxLines:
              1,
          overflow:
              TextOverflow.ellipsis,
        ),

        const SizedBox(
          height:
              8,
        ),

        LinearProgressIndicator(
          value:
              task.progress,
        ),

        const SizedBox(
          height:
              8,
        ),

        Row(
          children: [
            Expanded(
              child:
                  Text(
                _progressText(
                  task,
                ),
                style:
                    Theme.of(context)
                        .textTheme
                        .bodySmall,
              ),
            ),

            const Icon(
              Icons.chevron_right,
            ),
          ],
        ),

        if (task.bytesPerSecond >
            0) ...[
          const SizedBox(
            height:
                4,
          ),

          Row(
            children: [
              const Icon(
                Icons.speed,
                size:
                    15,
              ),

              const SizedBox(
                width:
                    5,
              ),

              Text(
                '${_formatSpeed(task.bytesPerSecond)}'
                '${_formatEta(task.estimatedRemaining)}',
                style:
                    Theme.of(context)
                        .textTheme
                        .bodySmall,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildIdle(
    BuildContext context,
    DownloadQueueService queue,
  ) {
    return Row(
      children: [
        Icon(
          queue.failedCount >
                  0
              ? Icons.error_outline
              : Icons
                  .download_done_outlined,
        ),

        const SizedBox(
          width:
              10,
        ),

        Expanded(
          child:
              Text(
            queue.failedCount >
                    0
                ? '${queue.failedCount} download(s) failed'
                : '${queue.completedCount} download(s) completed',
          ),
        ),

        const Icon(
          Icons.chevron_right,
        ),
      ],
    );
  }

  String _progressText(
    DownloadTask task,
  ) {
    final progress =
        task.progress;

    if (progress ==
        null) {
      return _formatSize(
        task.receivedBytes,
      );
    }

    return '${(progress * 100).toStringAsFixed(0)}% '
        '• ${_formatSize(task.receivedBytes)} '
        '/ ${_formatSize(task.totalBytes)}';
  }

  String _formatSpeed(
    double bytesPerSecond,
  ) {
    return '${_formatSize(bytesPerSecond.round())}/s';
  }

  String _formatEta(
    Duration? duration,
  ) {
    if (duration ==
        null) {
      return '';
    }

    if (duration.inSeconds <=
        0) {
      return '';
    }

    if (duration.inHours >
        0) {
      return ' • ~${duration.inHours}h '
          '${duration.inMinutes.remainder(60)}m';
    }

    if (duration.inMinutes >
        0) {
      return ' • ~${duration.inMinutes}m '
          '${duration.inSeconds.remainder(60)}s';
    }

    return ' • ~${duration.inSeconds}s';
  }

  String _formatSize(
    int bytes,
  ) {
    const kb =
        1024;

    const mb =
        kb * 1024;

    const gb =
        mb * 1024;

    if (bytes >=
        gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }

    if (bytes >=
        mb) {
      return '${(bytes / mb).toStringAsFixed(2)} MB';
    }

    if (bytes >=
        kb) {
      return '${(bytes / kb).toStringAsFixed(1)} KB';
    }

    return '$bytes B';
  }
}