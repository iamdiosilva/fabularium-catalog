import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/download_task.dart';
import '../models/telegram_group.dart';
import '../models/telegram_media.dart';
import '../models/telegram_message.dart';
import '../services/download_queue_service.dart';
import '../services/telegram_browse_worker.dart';
import '../services/telegram_file_service.dart';
import '../services/telegram_preview_manager.dart';
import '../widgets/download_queue_button.dart';

class TelegramMessagesPage extends StatefulWidget {
  final TelegramGroup group;

  const TelegramMessagesPage({
    super.key,
    required this.group,
  });

  @override
  State<TelegramMessagesPage> createState() =>
      _TelegramMessagesPageState();
}

class _TelegramMessagesPageState
    extends State<TelegramMessagesPage> {
  final TelegramBrowseWorker _browseWorker =
      TelegramBrowseWorker.instance;

  final TelegramPreviewManager _previewManager =
      TelegramPreviewManager.instance;

  bool _isLoading = true;
  bool _isRefreshing = false;

  String? _error;

  List<TelegramMessage> _messages = [];

  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();

    _previewManager.prepareForScreen();

    _loadMessages();
  }

  @override
  void dispose() {
    _requestGeneration++;

    _previewManager.cancelPending();

    super.dispose();
  }

  Future<void> _loadMessages({
    bool forceRefresh = false,
  }) async {
    final generation =
        ++_requestGeneration;

    if (forceRefresh &&
        _messages.isNotEmpty) {
      setState(() {
        _isRefreshing = true;
        _error = null;
      });
    } else {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final messages =
          await _browseWorker.getMessages(
        widget.group,
        limit: 50,
        forceRefresh: forceRefresh,
      );

      if (!mounted ||
          generation !=
              _requestGeneration) {
        return;
      }

      setState(() {
        _messages = messages;
        _isLoading = false;
        _isRefreshing = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted ||
          generation !=
              _requestGeneration) {
        return;
      }

      setState(() {
        _error = e.toString();
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.group.title,
        ),
        actions: [
          const DownloadQueueButton(),
          IconButton(
            tooltip: 'Refresh Messages',
            onPressed:
                _isLoading || _isRefreshing
                    ? null
                    : () {
                        _loadMessages(
                          forceRefresh: true,
                        );
                      },
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.refresh,
                  ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading &&
        _messages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(
              height: 16,
            ),
            Text(
              'Loading messages...',
            ),
          ],
        ),
      );
    }

    if (_error != null &&
        _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(
            24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
              ),
              const SizedBox(
                height: 16,
              ),
              Text(
                'Error loading messages',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge,
              ),
              const SizedBox(
                height: 12,
              ),
              Text(
                _error!,
                textAlign:
                    TextAlign.center,
              ),
              const SizedBox(
                height: 20,
              ),
              FilledButton.icon(
                onPressed: () {
                  _loadMessages(
                    forceRefresh: true,
                  );
                },
                icon: const Icon(
                  Icons.refresh,
                ),
                label: const Text(
                  'Try Again',
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 72,
            ),
            SizedBox(
              height: 16,
            ),
            Text(
              'No messages found.',
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (_isRefreshing)
          const LinearProgressIndicator(
            minHeight: 2,
          ),

        Expanded(
          child: ListView.separated(
            cacheExtent: 200,
            padding: const EdgeInsets.all(
              20,
            ),
            itemCount: _messages.length,
            separatorBuilder:
                (
              context,
              index,
            ) =>
                    const SizedBox(
              height: 12,
            ),
            itemBuilder:
                (
              context,
              index,
            ) {
              final message =
                  _messages[index];

              return RepaintBoundary(
                child: _MessageCard(
                  key: ValueKey<int>(
                    message.id,
                  ),
                  message: message,
                  groupTitle:
                      widget.group.title,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  final TelegramMessage message;

  final String groupTitle;

  const _MessageCard({
    super.key,
    required this.message,
    required this.groupTitle,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          16,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            _buildHeader(
              context,
            ),

            if (message.text
                .trim()
                .isNotEmpty) ...[
              const SizedBox(
                height: 12,
              ),
              SelectableText(
                message.text,
              ),
            ],

            if (message.media != null) ...[
              const SizedBox(
                height: 14,
              ),
              TelegramMediaCard(
                key: ValueKey<String>(
                  '${message.id}_${message.media!.cacheKey}',
                ),
                media: message.media!,
                groupTitle: groupTitle,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
  ) {
    return Row(
      children: [
        const Icon(
          Icons.person_outline,
          size: 18,
        ),

        const SizedBox(
          width: 8,
        ),

        Expanded(
          child: Text(
            message.sender,
            style: const TextStyle(
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ),

        if (message.date != null)
          Text(
            _formatDate(
              message.date!,
            ),
            style: Theme.of(context)
                .textTheme
                .bodySmall,
          ),
      ],
    );
  }

  String _formatDate(
    DateTime date,
  ) {
    final local =
        date.toLocal();

    String twoDigits(
      int value,
    ) =>
        value.toString().padLeft(
              2,
              '0',
            );

    return '${twoDigits(local.day)}/'
        '${twoDigits(local.month)}/'
        '${local.year} '
        '${twoDigits(local.hour)}:'
        '${twoDigits(local.minute)}';
  }
}

class TelegramMediaCard
    extends StatefulWidget {
  final TelegramMedia media;

  final String groupTitle;

  const TelegramMediaCard({
    super.key,
    required this.media,
    required this.groupTitle,
  });

  @override
  State<TelegramMediaCard> createState() =>
      _TelegramMediaCardState();
}

class _TelegramMediaCardState
    extends State<TelegramMediaCard> {
  final TelegramFileService _files =
      TelegramFileService.instance;

  final DownloadQueueService _queue =
      DownloadQueueService.instance;

  final TelegramPreviewManager _previewManager =
      TelegramPreviewManager.instance;

  late final ValueListenable<int>
      _downloadListenable;

  String? _previewPath;
  String? _previewError;

  bool _isLoadingPreview = false;

  @override
  void initState() {
    super.initState();

    _downloadListenable =
        _queue.listenableForMedia(
      widget.media,
      widget.groupTitle,
    );

    if (widget.media.hasPreview) {
      final cached =
          _previewManager.cachedPath(
        widget.media,
      );

      if (cached != null) {
        _previewPath = cached;
      } else {
        WidgetsBinding.instance
            .addPostFrameCallback(
          (_) {
            if (!mounted) {
              return;
            }

            _loadPreview();
          },
        );
      }
    }
  }

  Future<void> _loadPreview() async {
    if (_isLoadingPreview ||
        _previewPath != null) {
      return;
    }

    setState(() {
      _isLoadingPreview = true;
      _previewError = null;
    });

    try {
      final path =
          await _previewManager.getPreview(
        widget.media,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _previewPath = path;
        _previewError = null;
        _isLoadingPreview = false;
      });
    } on TelegramPreviewCancelledException {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingPreview = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _previewError = e.toString();
        _isLoadingPreview = false;
      });
    }
  }

  void _enqueue() {
    _queue.enqueue(
      media: widget.media,
      groupTitle:
          widget.groupTitle,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return ValueListenableBuilder<int>(
      valueListenable:
          _downloadListenable,
      builder:
          (
        context,
        revision,
        child,
      ) {
        final task =
            _queue.taskForMedia(
          widget.media,
          widget.groupTitle,
        );

        final downloadedPath =
            task?.filePath;

        return Container(
          width: double.infinity,
          padding:
              const EdgeInsets.all(
            14,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant,
            ),
            borderRadius:
                BorderRadius.circular(
              12,
            ),
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              if (widget.media.hasPreview)
                _buildPreview(
                  context,
                ),

              if (widget.media.hasPreview)
                const SizedBox(
                  height: 14,
                ),

              _buildFileInfo(
                context,
              ),

              if (task != null)
                _buildTaskStatus(
                  context,
                  task,
                ),

              const SizedBox(
                height: 14,
              ),

              _buildAction(
                task,
                downloadedPath,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFileInfo(
    BuildContext context,
  ) {
    final media =
        widget.media;

    return Row(
      children: [
        Icon(
          media.isPhoto
              ? Icons.image_outlined
              : Icons
                  .insert_drive_file_outlined,
          size: 30,
        ),

        const SizedBox(
          width: 12,
        ),

        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                media.fileName,
                maxLines: 2,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    const TextStyle(
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 4,
              ),

              Text(
                _formatSize(
                  media.size,
                ),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall,
              ),

              if (media.mimeType.isNotEmpty)
                Text(
                  media.mimeType,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTaskStatus(
    BuildContext context,
    DownloadTask task,
  ) {
    if (task.isQueued) {
      return const Padding(
        padding: EdgeInsets.only(
          top: 14,
        ),
        child: Row(
          children: [
            Icon(
              Icons.schedule,
              size: 18,
            ),
            SizedBox(
              width: 8,
            ),
            Text(
              'Waiting in download queue',
            ),
          ],
        ),
      );
    }

    if (task.isDownloading) {
      return Padding(
        padding: const EdgeInsets.only(
          top: 14,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: task.progress,
            ),

            const SizedBox(
              height: 6,
            ),

            Text(
              task.progress == null
                  ? 'Downloading...'
                  : '${(task.progress! * 100).toStringAsFixed(0)}% '
                      '• ${_formatSize(task.receivedBytes)}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall,
            ),
          ],
        ),
      );
    }

    if (task.isFailed) {
      return Padding(
        padding: const EdgeInsets.only(
          top: 14,
        ),
        child: Text(
          task.errorMessage ??
              'Download failed.',
          style: TextStyle(
            color: Theme.of(context)
                .colorScheme
                .error,
          ),
        ),
      );
    }

    if (task.isCompleted) {
      return const Padding(
        padding: EdgeInsets.only(
          top: 14,
        ),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 18,
            ),
            SizedBox(
              width: 8,
            ),
            Text(
              'Download completed',
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildAction(
    DownloadTask? task,
    String? downloadedPath,
  ) {
    if (downloadedPath != null) {
      return FilledButton.icon(
        onPressed: () {
          _files.showFileInExplorer(
            downloadedPath,
          );
        },
        icon: const Icon(
          Icons.folder_open,
        ),
        label: const Text(
          'Show in Folder',
        ),
      );
    }

    if (task == null) {
      return FilledButton.icon(
        onPressed: _enqueue,
        icon: const Icon(
          Icons.add_to_queue,
        ),
        label: const Text(
          'Add to Download Queue',
        ),
      );
    }

    if (task.isQueued) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: Icon(
          Icons.schedule,
        ),
        label: Text(
          'Queued',
        ),
      );
    }

    if (task.isDownloading) {
      return FilledButton.icon(
        onPressed: null,
        icon: SizedBox(
          width: 16,
          height: 16,
          child:
              CircularProgressIndicator(
            strokeWidth: 2,
          ),
        ),
        label: Text(
          'Downloading',
        ),
      );
    }

    if (task.isFailed) {
      return FilledButton.icon(
        onPressed: () {
          _queue.retry(
            task,
          );
        },
        icon: const Icon(
          Icons.refresh,
        ),
        label: const Text(
          'Retry Download',
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildPreview(
    BuildContext context,
  ) {
    if (_isLoadingPreview) {
      return Container(
        height: 180,
        width: double.infinity,
        alignment:
            Alignment.center,
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(
            8,
          ),
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest,
        ),
        child:
            const CircularProgressIndicator(),
      );
    }

    if (_previewPath != null) {
      return ClipRRect(
        borderRadius:
            BorderRadius.circular(
          8,
        ),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(
            maxHeight: 420,
          ),
          child: Image.file(
            File(
              _previewPath!,
            ),
            width: double.infinity,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality:
                FilterQuality.low,
            errorBuilder:
                (
              context,
              error,
              stackTrace,
            ) {
              return _previewPlaceholder(
                context,
                'Could not display preview.',
              );
            },
          ),
        ),
      );
    }

    if (_previewError != null) {
      return _previewPlaceholder(
        context,
        'Preview unavailable.',
      );
    }

    return const SizedBox.shrink();
  }

  Widget _previewPlaceholder(
    BuildContext context,
    String text,
  ) {
    return Container(
      height: 140,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(
          8,
        ),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
      ),
      child: Column(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            size: 36,
          ),
          const SizedBox(
            height: 8,
          ),
          Text(
            text,
          ),
        ],
      ),
    );
  }

  String _formatSize(
    int bytes,
  ) {
    if (bytes <= 0) {
      return 'Unknown size';
    }

    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }

    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(2)} MB';
    }

    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(1)} KB';
    }

    return '$bytes B';
  }
}