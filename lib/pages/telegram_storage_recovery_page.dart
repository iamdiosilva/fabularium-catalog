import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/telegram_storage_upload_journal.dart';
import '../models/telegram_storage_workspace.dart';
import '../services/telegram_storage_clean_service.dart';
import '../services/telegram_storage_package_recovery_service.dart';
import '../services/telegram_storage_package_uploader.dart';
import '../services/telegram_storage_upload_journal_service.dart';
import '../services/telegram_storage_verification_service.dart';

class TelegramStorageRecoveryPage
    extends StatefulWidget {
  const TelegramStorageRecoveryPage({
    super.key,
  });

  @override
  State<TelegramStorageRecoveryPage>
      createState() =>
          _TelegramStorageRecoveryPageState();
}

class _TelegramStorageRecoveryPageState
    extends State<TelegramStorageRecoveryPage> {
  final TelegramStorageUploadJournalService
      _journalService =
      TelegramStorageUploadJournalService.instance;

  final TelegramStoragePackageRecoveryService
      _packageRecoveryService =
      TelegramStoragePackageRecoveryService.instance;

  final TelegramStoragePackageUploader
      _packageUploader =
      TelegramStoragePackageUploader.instance;

  final TelegramStorageCleanService _cleanService =
      TelegramStorageCleanService.instance;

  List<TelegramStorageUploadJournal>
      _incompleteJournals =
      <TelegramStorageUploadJournal>[];

  TelegramStoragePackageUploadResult?
      _lastPackageUpload;

  bool _isLoading =
      true;

  bool _isUploadingPackage =
      false;

  bool _isCleaning =
      false;

  String? _cleaningPackageId;

  double _packageUploadProgress =
      0;

  String _packageUploadStage =
      '';

  String? _packageUploadFileName;

  String? _error;

  String? _status;

  bool get _isBusy =>
      _isUploadingPackage ||
      _isCleaning;

  @override
  void initState() {
    super.initState();

    _loadIncompleteJournals();
  }

  Future<void> _loadIncompleteJournals({
    bool showStatus = false,
  }) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading =
          true;
      _error =
          null;
    });

    try {
      final journals =
          await _journalService.listIncomplete();

      if (!mounted) {
        return;
      }

      setState(() {
        _incompleteJournals =
            journals;
        _isLoading =
            false;

        if (showStatus) {
          _status =
              journals.isEmpty
                  ? 'No incomplete uploads were found.'
                  : '${journals.length} incomplete upload'
                      '${journals.length == 1 ? '' : 's'} found.';
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading =
            false;
        _error =
            e.toString();
      });
    }
  }

  Future<void> _openJournalFolder() async {
    try {
      await _journalService
          .openJournalFolder();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error =
            e.toString();
      });
    }
  }

  int _publishedFileMessageCount(
    TelegramStorageUploadJournal journal,
  ) {
    int count =
        0;

    for (final group
        in journal.fileGroups.values) {
      count +=
          group.messageIds.length;
    }

    return count;
  }

  String _journalStatusLabel(
    TelegramStorageUploadStatus status,
  ) {
    return status.value
        .toUpperCase();
  }

  String _formatJournalDate(
    DateTime value,
  ) {
    final local =
        value.toLocal();

    String twoDigits(
      int number,
    ) =>
        number
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '${twoDigits(local.day)}/'
        '${twoDigits(local.month)}/'
        '${local.year} '
        '${twoDigits(local.hour)}:'
        '${twoDigits(local.minute)}';
  }

  bool _isRemoteMissing(
    TelegramStorageUploadJournal journal,
  ) {
    return TelegramStorageVerificationService
        .instance
        .isRemoteMissingJournal(
      journal,
    );
  }

  Future<void> _resumeJournal(
    TelegramStorageUploadJournal journal,
  ) async {
    if (_isBusy ||
        journal.isRemoving) {
      return;
    }

    if (_isRemoteMissing(
      journal,
    )) {
      setState(() {
        _error =
            'Resume is disabled because Telegram verification found '
            'missing remote messages for this package. Use Clean to '
            'remove the remaining recorded messages, then upload the '
            'model again from its catalog details page.';
      });

      return;
    }

    if (!_packageRecoveryService
        .hasRecoveryDescriptor(
      journal,
    )) {
      setState(() {
        _error =
            'This journal does not have a local recovery descriptor. '
            'It was probably created before Resume support was added.';
      });

      return;
    }

    setState(() {
      _error =
          null;
      _status =
          'Loading recovery package for ${journal.modelName}...';
    });

    try {
      final package =
          await _packageRecoveryService
              .loadForJournal(
        journal,
      );

      if (!mounted) {
        return;
      }

      final confirmed =
          await showDialog<
              bool>(
        context:
            context,
        builder:
            (
          context,
        ) {
          return AlertDialog(
            title:
                const Text(
              'Resume Storage Upload?',
            ),
            content:
                Text(
              '${journal.modelName}\n\n'
              'Status: ${_journalStatusLabel(journal.status)}\n'
              'Gallery messages: ${journal.galleryMessageIds.length}\n'
              'Completed file groups: ${journal.fileGroups.length}\n'
              'Manifest: ${journal.manifestMessageId ?? '-'}\n\n'
              'Catalog: ${journal.catalogChannel.title}\n'
              'Files: ${journal.filesChannel.title}\n\n'
              'Groups already recorded in the journal will not be '
              'uploaded again.',
            ),
            actions: [
              TextButton(
                onPressed:
                    () {
                  Navigator.of(
                    context,
                  ).pop(
                    false,
                  );
                },
                child:
                    const Text(
                  'Cancel',
                ),
              ),
              FilledButton.icon(
                onPressed:
                    () {
                  Navigator.of(
                    context,
                  ).pop(
                    true,
                  );
                },
                icon:
                    const Icon(
                  Icons.play_arrow_outlined,
                ),
                label:
                    const Text(
                  'Resume',
                ),
              ),
            ],
          );
        },
      );

      if (!mounted) {
        return;
      }

      if (confirmed !=
          true) {
        setState(() {
          _status =
              null;
        });

        return;
      }

      final recoveryWorkspace =
          TelegramStorageWorkspace(
        catalogChannel:
            journal.catalogChannel,
        filesChannel:
            journal.filesChannel,
      );

      setState(() {
        _isUploadingPackage =
            true;
        _packageUploadProgress =
            0;
        _packageUploadStage =
            'Resuming package upload...';
        _packageUploadFileName =
            null;
        _lastPackageUpload =
            null;
        _error =
            null;
        _status =
            null;
      });

      bool recoveryCardSynced =
          false;

      final result =
          await _packageUploader
              .uploadPackage(
        workspace:
            recoveryWorkspace,
        package:
            package,
        onProgress:
            (
          progress,
        ) {
          if (!mounted) {
            return;
          }

          if (!recoveryCardSynced) {
            recoveryCardSynced =
                true;

            unawaited(
              _refreshJournalsWithoutLoading(),
            );
          }

          setState(() {
            _packageUploadProgress =
                progress.overallProgress;
            _packageUploadStage =
                progress.stage;
            _packageUploadFileName =
                progress.currentFileName;
          });
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isUploadingPackage =
            false;
        _packageUploadProgress =
            1;
        _packageUploadStage =
            'Recovery completed successfully.';
        _lastPackageUpload =
            result;
        _status =
            result.alreadyUploaded
                ? 'The journal was already complete. Nothing was duplicated.'
                : 'Upload resumed successfully. Manifest message ID: '
                    '${result.manifestMessageId}.';
      });

      await _loadIncompleteJournals();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isUploadingPackage =
            false;
        _error =
            e.toString();
        _status =
            'Resume stopped. Completed groups remain persisted '
            'in the Storage V3 journal.';
      });

      await _loadIncompleteJournals();
    }
  }

  Future<void> _refreshJournalsWithoutLoading() async {
    try {
      final journals =
          await _journalService.listIncomplete();

      if (!mounted) {
        return;
      }

      setState(() {
        _incompleteJournals =
            journals;
      });
    } catch (_) {}
  }

  Future<void> _cleanJournal(
    TelegramStorageUploadJournal journal,
  ) async {
    if (_isBusy ||
        journal.isStored) {
      return;
    }

    final catalogCount =
        journal.catalogMessageIds.length;

    final filesCount =
        journal.filesMessageIds.length;

    final totalCount =
        catalogCount +
        filesCount;

    final confirmed =
        await showDialog<
            bool>(
      context:
          context,
      builder:
          (
        context,
      ) {
        return AlertDialog(
          title:
              const Text(
            'Clean Incomplete Upload?',
          ),
          content:
              Text(
            '${journal.modelName}\n\n'
            'This will permanently remove only the Telegram messages '
            'recorded by this incomplete upload journal.\n\n'
            'Catalog messages: $catalogCount\n'
            'Files messages: $filesCount\n'
            'Total Telegram messages: $totalCount\n\n'
            'After Telegram cleanup succeeds, the local staging folder '
            'and recovery journal will also be deleted.\n\n'
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed:
                  () {
                Navigator.of(
                  context,
                ).pop(
                  false,
                );
              },
              child:
                  const Text(
                'Cancel',
              ),
            ),
            FilledButton.icon(
              onPressed:
                  () {
                Navigator.of(
                  context,
                ).pop(
                  true,
                );
              },
              icon:
                  const Icon(
                Icons.delete_sweep_outlined,
              ),
              label:
                  const Text(
                'Clean',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed !=
            true ||
        !mounted) {
      return;
    }

    try {
      final removingJournal =
          await _journalService
              .markRemoving(
        journal,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isCleaning =
            true;
        _cleaningPackageId =
            journal.packageId;
        _error =
            null;
        _status =
            'Preparing cleanup for ${journal.modelName}...';

        final index =
            _incompleteJournals
                .indexWhere(
          (
            item,
          ) =>
              item.packageId ==
              journal.packageId,
        );

        if (index >=
            0) {
          final updated =
              List<TelegramStorageUploadJournal>.from(
            _incompleteJournals,
          );

          updated[
              index] =
              removingJournal;

          _incompleteJournals =
              updated;
        }
      });

      final result =
          await _cleanService.clean(
        journal:
            removingJournal,
        markRemoving:
            false,
        onProgress:
            (
          progress,
        ) {
          if (!mounted) {
            return;
          }

          setState(() {
            _status =
                progress.totalMessages <=
                        0
                    ? progress.stage
                    : '${progress.stage} '
                        '${progress.deletedMessages}/'
                        '${progress.totalMessages}';
          });
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isCleaning =
            false;
        _cleaningPackageId =
            null;
        _status =
            'Clean completed. '
            '${result.totalMessagesDeleted} Telegram message'
            '${result.totalMessagesDeleted == 1 ? '' : 's'} removed.';
        _error =
            null;
      });

      await _loadIncompleteJournals();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isCleaning =
            false;
        _cleaningPackageId =
            null;
        _error =
            e.toString();
        _status =
            'Clean stopped. The journal remains available so the '
            'operation can be retried safely.';
      });

      await _loadIncompleteJournals();
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar:
          AppBar(
        title:
            const Text(
          'Upload Recovery',
        ),
        actions: [
          IconButton(
            tooltip:
                'Open Journal Folder',
            onPressed:
                _isBusy
                    ? null
                    : _openJournalFolder,
            icon:
                const Icon(
              Icons.folder_open,
            ),
          ),
          IconButton(
            tooltip:
                'Refresh',
            onPressed:
                _isBusy
                    ? null
                    : () =>
                        _loadIncompleteJournals(
                          showStatus:
                              true,
                        ),
            icon:
                const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body:
          _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading &&
        _incompleteJournals
            .isEmpty) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    return ListView(
      padding:
          const EdgeInsets.all(
        24,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child:
                  Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    'Incomplete Uploads',
                    style:
                        Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                  ),
                  const SizedBox(
                    height:
                        4,
                  ),
                  const Text(
                    'Resume interrupted Storage V3 packages or clean '
                    'their recorded Telegram messages.',
                  ),
                ],
              ),
            ),
            Chip(
              label:
                  Text(
                '${_incompleteJournals.length} incomplete',
              ),
            ),
          ],
        ),
        if (_isUploadingPackage) ...[
          const SizedBox(
            height:
                20,
          ),
          _buildPackageUploadProgress(),
        ],
        if (_lastPackageUpload !=
            null) ...[
          const SizedBox(
            height:
                20,
          ),
          _buildUploadResultCard(
            _lastPackageUpload!,
          ),
        ],
        if (_status !=
            null) ...[
          const SizedBox(
            height:
                20,
          ),
          _buildStatusCard(),
        ],
        if (_error !=
            null) ...[
          const SizedBox(
            height:
                20,
          ),
          _buildErrorCard(),
        ],
        const SizedBox(
          height:
              20,
        ),
        if (_incompleteJournals.isEmpty)
          _buildEmptyCard()
        else
          ..._incompleteJournals.map(
            (
              journal,
            ) =>
                Padding(
              padding:
                  const EdgeInsets.only(
                bottom:
                    16,
              ),
              child:
                  _buildJournalCard(
                journal,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyCard() {
    return Card(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          24,
        ),
        child:
            Column(
          children: [
            const Icon(
              Icons.check_circle_outline,
              size:
                  56,
            ),
            const SizedBox(
              height:
                  12,
            ),
            const Text(
              'No incomplete uploads.',
              style:
                  TextStyle(
                fontSize:
                    17,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            const SizedBox(
              height:
                  6,
            ),
            Text(
              'Storage V3 has no package waiting for Resume or Clean.',
              style:
                  Theme.of(context)
                      .textTheme
                      .bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJournalCard(
    TelegramStorageUploadJournal journal,
  ) {
    final fileMessageCount =
        _publishedFileMessageCount(
      journal,
    );

    final hasRecoveryDescriptor =
        _packageRecoveryService
            .hasRecoveryDescriptor(
      journal,
    );

    return Card(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          18,
        ),
        child:
            Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Expanded(
                  child:
                      Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        journal.modelName,
                        style:
                            const TextStyle(
                          fontSize:
                              17,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height:
                            4,
                      ),
                      SelectableText(
                        journal.packageId,
                        style:
                            Theme.of(context)
                                .textTheme
                                .bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  width:
                      12,
                ),
                Chip(
                  label:
                      Text(
                    _journalStatusLabel(
                      journal.status,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(
              height:
                  14,
            ),
            Wrap(
              spacing:
                  18,
              runSpacing:
                  8,
              children: [
                Text(
                  'Gallery: ${journal.galleryMessageIds.length}',
                ),
                Text(
                  'File groups: ${journal.fileGroups.length}',
                ),
                Text(
                  'File messages: $fileMessageCount',
                ),
                Text(
                  'Manifest: ${journal.manifestMessageId ?? '-'}',
                ),
              ],
            ),
            const SizedBox(
              height:
                  12,
            ),
            Text(
              'Catalog: ${journal.catalogChannel.title}',
            ),
            Text(
              'Files: ${journal.filesChannel.title}',
            ),
            Text(
              'Updated: ${_formatJournalDate(journal.updatedAt)}',
            ),
            const SizedBox(
              height:
                  8,
            ),
            FutureBuilder<bool>(
              future:
                  Directory(
                journal.stagingDirectoryPath,
              ).exists(),
              builder:
                  (
                context,
                snapshot,
              ) {
                final exists =
                    snapshot.data;

                return Row(
                  children: [
                    Icon(
                      exists ==
                              false
                          ? Icons.folder_off_outlined
                          : Icons.folder_outlined,
                      size:
                          18,
                    ),
                    const SizedBox(
                      width:
                          8,
                    ),
                    Text(
                      exists ==
                              null
                          ? 'Staging: checking...'
                          : exists
                              ? 'Staging: available locally'
                              : 'Staging: missing locally',
                    ),
                  ],
                );
              },
            ),
            if (journal.lastError !=
                    null &&
                journal.lastError!
                    .trim()
                    .isNotEmpty) ...[
              const SizedBox(
                height:
                    12,
              ),
              Container(
                width:
                    double.infinity,
                padding:
                    const EdgeInsets.all(
                  12,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      Theme.of(context)
                          .colorScheme
                          .errorContainer,
                  borderRadius:
                      BorderRadius.circular(
                    10,
                  ),
                ),
                child:
                    Text(
                  journal.lastError!,
                  style:
                      TextStyle(
                    color:
                        Theme.of(context)
                            .colorScheme
                            .onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(
              height:
                  14,
            ),
            Wrap(
              spacing:
                  12,
              runSpacing:
                  8,
              crossAxisAlignment:
                  WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed:
                      _isBusy ||
                              journal.isRemoving ||
                              _isRemoteMissing(
                                journal,
                              ) ||
                              !hasRecoveryDescriptor
                          ? null
                          : () =>
                              _resumeJournal(
                                journal,
                              ),
                  icon:
                      const Icon(
                    Icons.play_arrow_outlined,
                  ),
                  label:
                      const Text(
                    'Resume',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _isBusy
                          ? null
                          : () =>
                              _cleanJournal(
                                journal,
                              ),
                  icon:
                      _cleaningPackageId ==
                              journal.packageId
                          ? const SizedBox(
                              width:
                                  16,
                              height:
                                  16,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth:
                                    2,
                              ),
                            )
                          : const Icon(
                              Icons.delete_sweep_outlined,
                            ),
                  label:
                      Text(
                    _cleaningPackageId ==
                            journal.packageId
                        ? 'Cleaning...'
                        : 'Clean',
                  ),
                ),
                if (_isRemoteMissing(
                  journal,
                ))
                  Text(
                    'Resume unavailable: Telegram messages are missing. '
                    'Use Clean before uploading again.',
                    style:
                        TextStyle(
                      color:
                          Theme.of(context)
                              .colorScheme
                              .error,
                      fontWeight:
                          FontWeight.w600,
                    ),
                  )
                else if (hasRecoveryDescriptor)
                  const Chip(
                    visualDensity:
                        VisualDensity.compact,
                    avatar:
                        Icon(
                      Icons.save_outlined,
                      size:
                          16,
                    ),
                    label:
                        Text(
                      'Recovery package available',
                    ),
                  )
                else
                  Text(
                    'Resume unavailable: no recovery descriptor.',
                    style:
                        Theme.of(context)
                            .textTheme
                            .bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackageUploadProgress() {
    return Card(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          16,
        ),
        child:
            Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'Resuming Storage Package',
              style:
                  TextStyle(
                fontSize:
                    17,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            const SizedBox(
              height:
                  8,
            ),
            Text(
              _packageUploadStage,
            ),
            if (_packageUploadFileName !=
                null) ...[
              const SizedBox(
                height:
                    4,
              ),
              Text(
                _packageUploadFileName!,
              ),
            ],
            const SizedBox(
              height:
                  10,
            ),
            LinearProgressIndicator(
              value:
                  _packageUploadProgress,
            ),
            const SizedBox(
              height:
                  6,
            ),
            Text(
              '${(_packageUploadProgress * 100).toStringAsFixed(0)}%',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadResultCard(
    TelegramStoragePackageUploadResult result,
  ) {
    return Card(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          16,
        ),
        child:
            Row(
          children: [
            const Icon(
              Icons.cloud_done_outlined,
            ),
            const SizedBox(
              width:
                  12,
            ),
            Expanded(
              child:
                  Text(
                'Recovery completed. Manifest message ID: '
                '${result.manifestMessageId}.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          14,
        ),
        child:
            Row(
          children: [
            const Icon(
              Icons.info_outline,
            ),
            const SizedBox(
              width:
                  10,
            ),
            Expanded(
              child:
                  Text(
                _status!,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          14,
        ),
        child:
            Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color:
                  Theme.of(context)
                      .colorScheme
                      .error,
            ),
            const SizedBox(
              width:
                  10,
            ),
            Expanded(
              child:
                  Text(
                _error!,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
