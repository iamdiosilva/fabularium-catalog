import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../models/telegram_storage_upload_journal.dart';
import '../../application/telegram_storage_recovery_controller.dart';

class TelegramStorageRecoveryPage extends StatefulWidget {
  const TelegramStorageRecoveryPage({super.key});

  @override
  State<TelegramStorageRecoveryPage> createState() =>
      _TelegramStorageRecoveryPageState();
}

class _TelegramStorageRecoveryPageState
    extends State<TelegramStorageRecoveryPage> {
  late final TelegramStorageRecoveryController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TelegramStorageRecoveryController()
      ..addListener(_onChanged)
      ..load();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _runResume(TelegramStorageUploadJournal journal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resume Storage Upload?'),
        content: Text(
          '${journal.modelName}\n\n'
          'Status: ${journal.status.value.toUpperCase()}\n'
          'Gallery messages: ${journal.galleryMessageIds.length}\n'
          'Completed file groups: ${journal.fileGroups.length}\n'
          'Manifest: ${journal.manifestMessageId ?? '-'}\n\n'
          'Groups already recorded in the journal will not be uploaded again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.play_arrow_outlined),
            label: const Text('Resume'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      await _controller.resume(journal);
    } catch (_) {}
  }

  Future<void> _runRepair(TelegramStorageUploadJournal journal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Repair Telegram Upload?'),
        content: Text(
          '${journal.modelName}\n\n'
          'Repair compares every recorded message ID with Telegram.\n\n'
          'If only part of a gallery or file group remains, Fabularium removes '
          'the surviving messages from that partial group and resets the group '
          'in the journal. Resume can then upload that complete group again '
          'without duplicating healthy groups.\n\n'
          'No local model files are deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.build_circle_outlined),
            label: const Text('Repair'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      await _controller.repair(journal);
    } catch (_) {}
  }

  Future<void> _runClean(TelegramStorageUploadJournal journal) async {
    final catalogCount = journal.catalogMessageIds.length;
    final filesCount = journal.filesMessageIds.length;
    final total = catalogCount + filesCount;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clean Incomplete Upload?'),
        content: Text(
          '${journal.modelName}\n\n'
          'This permanently removes only Telegram messages recorded by this '
          'journal.\n\n'
          'Catalog messages: $catalogCount\n'
          'Files messages: $filesCount\n'
          'Total Telegram messages: $total\n\n'
          'After remote cleanup, staging and the upload journal are deleted.\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Clean'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      await _controller.clean(journal);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Recovery'),
        actions: [
          IconButton(
            tooltip: 'Open Journal Folder',
            onPressed: _controller.isBusy
                ? null
                : () async {
                    try {
                      await _controller.openJournalFolder();
                    } catch (_) {}
                  },
            icon: const Icon(Icons.folder_open),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _controller.isBusy
                ? null
                : () => _controller.load(showStatus: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_controller.isLoading && _controller.journals.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Incomplete Uploads',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Verify, Repair, Resume or Clean persistent Storage V3 uploads.',
                  ),
                ],
              ),
            ),
            Chip(label: Text('${_controller.journals.length} incomplete')),
          ],
        ),
        if (_controller.isUploading || _controller.isRepairing) ...[
          const SizedBox(height: 20),
          _buildProgressCard(),
        ],
        if (_controller.status != null) ...[
          const SizedBox(height: 20),
          _messageCard(
            icon: Icons.info_outline,
            message: _controller.status!,
          ),
        ],
        if (_controller.error != null) ...[
          const SizedBox(height: 20),
          _messageCard(
            icon: Icons.error_outline,
            message: _controller.error!,
            error: true,
          ),
        ],
        const SizedBox(height: 20),
        if (_controller.journals.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.check_circle_outline, size: 56),
                  const SizedBox(height: 12),
                  const Text(
                    'No incomplete uploads.',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Storage V3 has no package waiting for Repair, Resume or Clean.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          )
        else
          ..._controller.journals.map(
            (journal) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildJournalCard(journal),
            ),
          ),
      ],
    );
  }

  Widget _buildJournalCard(TelegramStorageUploadJournal journal) {
    final remoteMissing = _controller.isRemoteMissing(journal);
    final recoveryAvailable = _controller.hasRecoveryDescriptor(journal);
    final busyThis = _controller.activePackageId == journal.packageId;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        journal.modelName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        journal.packageId,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Chip(label: Text(journal.status.value.toUpperCase())),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                Text('Gallery: ${journal.galleryMessageIds.length}'),
                Text('File groups: ${journal.fileGroups.length}'),
                Text('File messages: ${_fileMessageCount(journal)}'),
                Text('Manifest: ${journal.manifestMessageId ?? '-'}'),
              ],
            ),
            const SizedBox(height: 12),
            Text('Catalog: ${journal.catalogChannel.title}'),
            Text('Files: ${journal.filesChannel.title}'),
            Text('Updated: ${_formatDate(journal.updatedAt)}'),
            const SizedBox(height: 8),
            FutureBuilder<bool>(
              future: Directory(journal.stagingDirectoryPath).exists(),
              builder: (context, snapshot) {
                final exists = snapshot.data;
                return Row(
                  children: [
                    Icon(
                      exists == false
                          ? Icons.folder_off_outlined
                          : Icons.folder_outlined,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      exists == null
                          ? 'Staging: checking...'
                          : exists
                              ? 'Staging: available locally'
                              : 'Staging: missing locally',
                    ),
                  ],
                );
              },
            ),
            if (journal.lastError?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: remoteMissing
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(journal.lastError!),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _controller.isBusy ||
                          journal.isRemoving ||
                          remoteMissing ||
                          !recoveryAvailable
                      ? null
                      : () => _runResume(journal),
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: const Text('Resume'),
                ),
                OutlinedButton.icon(
                  onPressed: _controller.isBusy ||
                          journal.isRemoving ||
                          !recoveryAvailable
                      ? null
                      : () => _runRepair(journal),
                  icon: busyThis && _controller.isRepairing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.build_circle_outlined),
                  label: Text(
                    busyThis && _controller.isRepairing
                        ? 'Repairing...'
                        : 'Repair',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _controller.isBusy ? null : () => _runClean(journal),
                  icon: busyThis && _controller.isCleaning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_sweep_outlined),
                  label: Text(
                    busyThis && _controller.isCleaning ? 'Cleaning...' : 'Clean',
                  ),
                ),
                if (remoteMissing)
                  Text(
                    'Telegram messages are missing. Repair before Resume.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else if (recoveryAvailable)
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(Icons.save_outlined, size: 16),
                    label: Text('Recovery package available'),
                  )
                else
                  Text(
                    'Repair/Resume unavailable: no recovery descriptor.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _controller.isRepairing
                  ? 'Repairing Storage Package'
                  : 'Resuming Storage Package',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_controller.progressStage),
            if (_controller.progressFileName != null) ...[
              const SizedBox(height: 4),
              Text(_controller.progressFileName!),
            ],
            const SizedBox(height: 10),
            LinearProgressIndicator(value: _controller.progress),
            const SizedBox(height: 6),
            Text('${(_controller.progress * 100).toStringAsFixed(0)}%'),
          ],
        ),
      ),
    );
  }

  Widget _messageCard({
    required IconData icon,
    required String message,
    bool error = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: error ? Theme.of(context).colorScheme.error : null,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  int _fileMessageCount(TelegramStorageUploadJournal journal) {
    var result = 0;
    for (final group in journal.fileGroups.values) {
      result += group.messageIds.length;
    }
    return result;
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
