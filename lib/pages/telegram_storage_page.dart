import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/telegram_storage_channel.dart';
import '../models/telegram_storage_package.dart';
import '../models/telegram_storage_upload_journal.dart';
import '../models/telegram_storage_workspace.dart';
import '../services/telegram_storage_package_recovery_service.dart';
import '../services/telegram_storage_package_uploader.dart';
import '../services/telegram_storage_packager.dart';
import '../services/telegram_storage_service.dart';
import '../services/telegram_storage_upload_journal_service.dart';
import '../services/telegram_storage_workspace_service.dart';

enum _TelegramStorageChannelRole {
  catalog,
  files,
}

class TelegramStoragePage extends StatefulWidget {
  const TelegramStoragePage({
    super.key,
  });

  @override
  State<TelegramStoragePage> createState() => _TelegramStoragePageState();
}

class _TelegramStoragePageState extends State<TelegramStoragePage> {
  final TelegramStorageService _storage =
      TelegramStorageService.instance;

  final TelegramStorageWorkspaceService _workspaceService =
      TelegramStorageWorkspaceService.instance;

  final TelegramStoragePackager _packager =
      TelegramStoragePackager.instance;

  final TelegramStoragePackageUploader _packageUploader =
      TelegramStoragePackageUploader.instance;

  final TelegramStoragePackageRecoveryService _packageRecoveryService =
      TelegramStoragePackageRecoveryService.instance;

  final TelegramStorageUploadJournalService _journalService =
      TelegramStorageUploadJournalService.instance;

  TelegramStorageWorkspace _workspace =
      const TelegramStorageWorkspace.empty();

  TelegramStoragePackage? _preparedPackage;

  TelegramStoragePackageUploadResult? _lastPackageUpload;

  List<TelegramStorageUploadJournal> _incompleteJournals =
      <TelegramStorageUploadJournal>[];

  bool _isLoadingJournals = false;
  String? _journalError;

  bool _isLoading = true;
  bool _isCreatingChannel = false;
  bool _isLoadingChannels = false;
  bool _isUploading = false;
  bool _isPackaging = false;
  bool _isUploadingPackage = false;

  double _uploadProgress = 0;
  double _packageProgress = 0;
  double _packageUploadProgress = 0;

  String _packageStage = '';
  String _packageUploadStage = '';

  String? _packageUploadFileName;
  String? _error;
  String? _status;
  String? _currentFileName;

  TelegramStorageChannel? get _filesChannel =>
      _workspace.filesChannel;

  int get _configuredChannelCount =>
      (_workspace.hasCatalogChannel ? 1 : 0) +
      (_workspace.hasFilesChannel ? 1 : 0);

  bool get _isBusy =>
      _isCreatingChannel ||
      _isLoadingChannels ||
      _isUploading ||
      _isPackaging ||
      _isUploadingPackage;

  @override
  void initState() {
    super.initState();

    _loadStorage();
  }

  // ============================================================
  // STORAGE V3 WORKSPACE
  // ============================================================

  Future<void> _loadStorage() async {
    try {
      final workspace =
          await _workspaceService.load();

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace = workspace;
        _isLoading = false;
      });

      await _loadIncompleteJournals();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  String _channelRoleTitle(
    _TelegramStorageChannelRole role,
  ) {
    return role == _TelegramStorageChannelRole.catalog
        ? 'Catalog Channel'
        : 'Files Channel';
  }

  String _channelRoleDescription(
    _TelegramStorageChannelRole role,
  ) {
    return role == _TelegramStorageChannelRole.catalog
        ? 'Stores galleries, preview images and model metadata.'
        : 'Stores ZIP files, split parts and package manifests.';
  }

  TelegramStorageChannel? _channelForRole(
    _TelegramStorageChannelRole role,
  ) {
    return role == _TelegramStorageChannelRole.catalog
        ? _workspace.catalogChannel
        : _workspace.filesChannel;
  }

  TelegramStorageChannel? _otherChannelForRole(
    _TelegramStorageChannelRole role,
  ) {
    return role == _TelegramStorageChannelRole.catalog
        ? _workspace.filesChannel
        : _workspace.catalogChannel;
  }

  Future<void> _createWorkspaceChannel(
    _TelegramStorageChannelRole role,
  ) async {
    if (_isBusy) {
      return;
    }

    final roleTitle =
        _channelRoleTitle(role);

    setState(() {
      _isCreatingChannel = true;
      _error = null;
      _status =
          'Creating $roleTitle...';
    });

    try {
      final workspace =
          role == _TelegramStorageChannelRole.catalog
              ? await _workspaceService
                  .createCatalogChannel()
              : await _workspaceService
                  .createFilesChannel();

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace = workspace;
        _isCreatingChannel = false;
        _error = null;
        _status =
            '$roleTitle created and configured successfully.';

        if (role == _TelegramStorageChannelRole.files) {
          _lastPackageUpload = null;
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isCreatingChannel = false;
        _status = null;
        _error = e.toString();
      });
    }
  }

  Future<void> _selectExistingChannel(
    _TelegramStorageChannelRole role,
  ) async {
    if (_isBusy) {
      return;
    }

    final roleTitle =
        _channelRoleTitle(role);

    final otherChannel =
        _otherChannelForRole(role);

    setState(() {
      _isLoadingChannels = true;
      _error = null;
      _status =
          'Loading private Telegram channels...';
    });

    try {
      final channels =
          await _workspaceService
              .listAvailableChannels();

      if (!mounted) {
        return;
      }

      final selectableChannels =
          channels
              .where(
                (channel) =>
                    channel.id !=
                    otherChannel?.id,
              )
              .toList();

      setState(() {
        _isLoadingChannels = false;
        _status = null;
      });

      if (selectableChannels.isEmpty) {
        setState(() {
          _error =
              otherChannel == null
                  ? 'No writable private Telegram channels '
                      'were found in the recent dialog list.'
                  : 'No other writable private Telegram channel '
                      'is available. Catalog Channel and Files '
                      'Channel must be different.';
        });

        return;
      }

      final selected =
          await showDialog<TelegramStorageChannel>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(
              'Select $roleTitle',
            ),
            content: SizedBox(
              width: 560,
              height: 420,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    _channelRoleDescription(
                      role,
                    ),
                    style:
                        Theme.of(context)
                            .textTheme
                            .bodyMedium,
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  const Text(
                    'Choose a private channel where this '
                    'Telegram account can publish.',
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount:
                          selectableChannels
                              .length,
                      separatorBuilder:
                          (
                            context,
                            index,
                          ) =>
                              const Divider(
                        height: 1,
                      ),
                      itemBuilder:
                          (
                            context,
                            index,
                          ) {
                        final channel =
                            selectableChannels[
                                index];

                        return ListTile(
                          leading:
                              const CircleAvatar(
                            child: Icon(
                              Icons.lock_outline,
                            ),
                          ),
                          title: Text(
                            channel.title,
                          ),
                          subtitle: Text(
                            'Private channel • ID ${channel.id}',
                          ),
                          trailing:
                              const Icon(
                            Icons.chevron_right,
                          ),
                          onTap: () {
                            Navigator.of(
                              context,
                            ).pop(
                              channel,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(
                    context,
                  ).pop();
                },
                child: const Text(
                  'Cancel',
                ),
              ),
            ],
          );
        },
      );

      if (selected == null ||
          !mounted) {
        return;
      }

      final workspace =
          role == _TelegramStorageChannelRole.catalog
              ? await _workspaceService
                  .selectCatalogChannel(
                  selected,
                )
              : await _workspaceService
                  .selectFilesChannel(
                  selected,
                );

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace = workspace;
        _error = null;
        _status =
            'Using "${selected.title}" as $roleTitle.';

        if (role == _TelegramStorageChannelRole.files) {
          _lastPackageUpload = null;
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingChannels = false;
        _status = null;
        _error = e.toString();
      });
    }
  }

  Future<void> _forgetWorkspaceChannel(
    _TelegramStorageChannelRole role,
  ) async {
    if (_isBusy) {
      return;
    }

    final channel =
        _channelForRole(role);

    if (channel == null) {
      return;
    }

    final roleTitle =
        _channelRoleTitle(role);

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Forget $roleTitle?',
          ),
          content: Text(
            'This removes only the local $roleTitle '
            'configuration. Nothing will be deleted '
            'from Telegram.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  context,
                ).pop(
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(
                  context,
                ).pop(
                  true,
                );
              },
              child: const Text(
                'Forget',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true ||
        !mounted) {
      return;
    }

    try {
      final workspace =
          role == _TelegramStorageChannelRole.catalog
              ? await _workspaceService
                  .clearCatalogChannel()
              : await _workspaceService
                  .clearFilesChannel();

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace = workspace;
        _error = null;
        _status =
            '$roleTitle configuration removed.';

        if (role == _TelegramStorageChannelRole.files) {
          _lastPackageUpload = null;
          _uploadProgress = 0;
          _currentFileName = null;
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = e.toString();
      });
    }
  }

  // ============================================================
  // UPLOAD RECOVERY JOURNALS
  // ============================================================

  Future<void> _loadIncompleteJournals({
    bool showStatus = false,
  }) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoadingJournals = true;
      _journalError = null;
    });

    try {
      final journals =
          await _journalService.listIncomplete();

      if (!mounted) {
        return;
      }

      setState(() {
        _incompleteJournals = journals;
        _isLoadingJournals = false;

        if (showStatus) {
          _status = journals.isEmpty
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
        _isLoadingJournals = false;
        _journalError = e.toString();
      });
    }
  }

  Future<void> _openJournalFolder() async {
    try {
      await _journalService.openJournalFolder();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _journalError = e.toString();
      });
    }
  }

  int _publishedFileMessageCount(
    TelegramStorageUploadJournal journal,
  ) {
    int count = 0;

    for (final group in journal.fileGroups.values) {
      count += group.messageIds.length;
    }

    return count;
  }

  String _journalStatusLabel(
    TelegramStorageUploadStatus status,
  ) {
    return status.value.toUpperCase();
  }

  String _formatJournalDate(
    DateTime value,
  ) {
    final local = value.toLocal();

    String twoDigits(int number) =>
        number.toString().padLeft(2, '0');

    return '${twoDigits(local.day)}/'
        '${twoDigits(local.month)}/'
        '${local.year} '
        '${twoDigits(local.hour)}:'
        '${twoDigits(local.minute)}';
  }

  // ============================================================
  // RESUME JOURNAL
  // ============================================================

  Future<void> _resumeJournal(
    TelegramStorageUploadJournal journal,
  ) async {
    if (_isBusy ||
        journal.isRemoving) {
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
      _error = null;
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
          await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text(
              'Resume Storage Upload?',
            ),
            content: Text(
              '${journal.modelName}\n\n'
              'Status: ${_journalStatusLabel(journal.status)}\n'
              'Gallery messages: ${journal.galleryMessageIds.length}\n'
              'Completed file groups: ${journal.fileGroups.length}\n'
              'Manifest: ${journal.manifestMessageId ?? '-'}\n\n'
              'The upload will continue using the original channels:\n'
              'Catalog: ${journal.catalogChannel.title}\n'
              'Files: ${journal.filesChannel.title}\n\n'
              'Groups already recorded in the journal will not be '
              'uploaded again.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(
                    context,
                  ).pop(
                    false,
                  );
                },
                child: const Text(
                  'Cancel',
                ),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(
                    context,
                  ).pop(
                    true,
                  );
                },
                icon: const Icon(
                  Icons.play_arrow_outlined,
                ),
                label: const Text(
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

      if (confirmed != true) {
        setState(() {
          _status = null;
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
        _preparedPackage =
            package;
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

      bool recoveryCardSynced = false;

      final result =
          await _packageUploader
              .uploadPackage(
        workspace:
            recoveryWorkspace,
        package:
            package,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }

          if (!recoveryCardSynced) {
            recoveryCardSynced = true;

            unawaited(
              _loadIncompleteJournals(),
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

  // ============================================================
  // TEST UPLOAD
  // ============================================================

  Future<void> _pickAndUpload() async {
    final channel =
        _filesChannel;

    if (channel == null ||
        _isBusy) {
      return;
    }

    final selection =
        await FilePicker.platform
            .pickFiles(
      allowMultiple: false,
    );

    if (selection == null ||
        selection.files.isEmpty) {
      return;
    }

    final selected =
        selection.files.single;

    final path =
        selected.path;

    if (path == null ||
        path.isEmpty) {
      return;
    }

    if (selected.size >
        TelegramStorageService
            .maxStorageFileBytes) {
      setState(() {
        _error =
            'This file exceeds the single-file '
            'Telegram Storage limit.';
      });

      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
      _currentFileName =
          selected.name;
      _error = null;
      _status =
          'Uploading ${selected.name} to Files Channel...';
    });

    try {
      final result =
          await _storage.uploadFile(
        channel: channel,
        filePath: path,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }

          setState(() {
            _uploadProgress =
                progress;
          });
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isUploading = false;
        _uploadProgress = 1;
        _status =
            result.messageId != null
                ? '${result.fileName} uploaded successfully. '
                    'Telegram message ID: ${result.messageId}.'
                : '${result.fileName} uploaded successfully.';
        _currentFileName = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isUploading = false;
        _error = e.toString();
        _status = null;
        _currentFileName = null;
      });
    }
  }

  // ============================================================
  // PREPARE MODEL
  // ============================================================

  Future<void> _pickAndPrepareFolder() async {
    if (_filesChannel == null ||
        _isBusy) {
      return;
    }

    final folderPath =
        await FilePicker.platform
            .getDirectoryPath(
      dialogTitle:
          'Select Model Folder',
    );

    if (folderPath == null ||
        folderPath.trim().isEmpty) {
      return;
    }

    setState(() {
      _isPackaging = true;
      _packageProgress = 0;
      _packageStage =
          'Preparing...';
      _preparedPackage = null;
      _lastPackageUpload = null;
      _error = null;
      _status = null;
    });

    try {
      final package =
          await _packager.prepareFolder(
        folderPath: folderPath,
        onProgress:
            (
              progress,
              stage,
            ) {
          if (!mounted) {
            return;
          }

          setState(() {
            _packageProgress =
                progress;
            _packageStage =
                stage;
          });
        },
      );

      await _packageRecoveryService.savePackage(
        package,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _preparedPackage =
            package;
        _packageProgress = 1;
        _packageStage =
            'Package ready.';
        _isPackaging = false;
        _status =
            package.isSplit
                ? 'Package prepared in '
                    '${package.partCount} parts.'
                : 'Package prepared as a single ZIP.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isPackaging = false;
        _packageProgress = 0;
        _packageStage = '';
        _error = e.toString();
      });
    }
  }

  // ============================================================
  // UPLOAD PREPARED PACKAGE
  // ============================================================

  Future<void> _uploadPreparedPackage() async {
    final package =
        _preparedPackage;

    if (!_workspace.isFullyConfigured ||
        package == null ||
        _isBusy) {
      return;
    }

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Upload Storage Package?',
          ),
          content: Text(
            '${package.sourceFolderName}\n\n'
            '${package.partCount} storage '
            '${package.partCount == 1 ? 'file' : 'files'}\n'
            '${_formatSize(package.totalUploadSize)}\n\n'
            'Storage V3 will publish the gallery in the '
            'Catalog Channel, send file groups to the '
            'Files Channel, persist the journal after each '
            'completed group and upload the manifest last.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  context,
                ).pop(
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(
                  context,
                ).pop(
                  true,
                );
              },
              icon: const Icon(
                Icons.cloud_upload_outlined,
              ),
              label: const Text(
                'Upload',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true ||
        !mounted) {
      return;
    }

    setState(() {
      _isUploadingPackage = true;
      _packageUploadProgress = 0;
      _packageUploadStage =
          'Starting package upload...';
      _packageUploadFileName = null;
      _lastPackageUpload = null;
      _error = null;
      _status = null;
    });

    try {
      bool recoveryCardSynced = false;

      final result =
          await _packageUploader
              .uploadPackage(
        workspace: _workspace,
        package: package,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }

          if (!recoveryCardSynced) {
            recoveryCardSynced = true;

            unawaited(
              _loadIncompleteJournals(),
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
        _isUploadingPackage = false;
        _packageUploadProgress = 1;
        _packageUploadStage =
            'Package stored successfully.';
        _lastPackageUpload =
            result;
        _status =
            result.alreadyUploaded
                ? 'This package was already stored '
                    'in Telegram. Nothing was duplicated.'
                : 'Package uploaded successfully. '
                    'Manifest message ID: '
                    '${result.manifestMessageId}.';
      });

      await _loadIncompleteJournals();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isUploadingPackage = false;
        _error = e.toString();
        _status =
            'Package upload was interrupted. '
            'The Storage V3 journal was marked FAILED '
            'and completed groups remain persisted.';
      });

      await _loadIncompleteJournals();
    }
  }

  // ============================================================
  // PACKAGE ACTIONS
  // ============================================================

  Future<void> _openPreparedPackage() async {
    final package =
        _preparedPackage;

    if (package == null) {
      return;
    }

    try {
      await _packager
          .openPackageFolder(
        package,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _deletePreparedPackage() async {
    final package =
        _preparedPackage;

    if (package == null ||
        _isBusy) {
      return;
    }

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Delete Prepared Package?',
          ),
          content: const Text(
            'The temporary ZIP, parts, manifest '
            'and upload receipt will be deleted. '
            'The original model folder and Telegram '
            'files will not be changed.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  context,
                ).pop(
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(
                  context,
                ).pop(
                  true,
                );
              },
              child: const Text(
                'Delete',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _packager.deletePackage(
        package,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _preparedPackage = null;
        _lastPackageUpload = null;
        _status =
            'Prepared package deleted.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = e.toString();
      });
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Telegram Storage',
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
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
        Text(
          'Fabularium Telegram Storage V3',
          style:
              Theme.of(context)
                  .textTheme
                  .headlineSmall,
        ),
        const SizedBox(
          height: 8,
        ),
        const Text(
          'Catalog content and package files use '
          'separate private Telegram channels.',
        ),
        const SizedBox(
          height: 24,
        ),
        _buildUploadRecoveryCard(),
        const SizedBox(
          height: 20,
        ),
        _buildWorkspaceCard(),
        if (_filesChannel != null) ...[
          const SizedBox(
            height: 20,
          ),
          _buildFilesOperationsCard(
            _filesChannel!,
          ),
        ],
        if (_isPackaging) ...[
          const SizedBox(
            height: 20,
          ),
          _buildPackagingProgress(),
        ],
        if (_preparedPackage != null) ...[
          const SizedBox(
            height: 20,
          ),
          _buildPreparedPackageCard(
            _preparedPackage!,
          ),
        ],
        if (_isUploadingPackage) ...[
          const SizedBox(
            height: 20,
          ),
          _buildPackageUploadProgress(),
        ],
        if (_lastPackageUpload != null) ...[
          const SizedBox(
            height: 20,
          ),
          _buildUploadResultCard(
            _lastPackageUpload!,
          ),
        ],
        if (_isUploading) ...[
          const SizedBox(
            height: 20,
          ),
          _buildUploadProgress(),
        ],
        if (_status != null) ...[
          const SizedBox(
            height: 20,
          ),
          _buildStatusCard(),
        ],
        if (_error != null) ...[
          const SizedBox(
            height: 20,
          ),
          _buildErrorCard(),
        ],
        const SizedBox(
          height: 24,
        ),
        _buildPhaseCard(),
      ],
    );
  }

  // ============================================================
  // UPLOAD RECOVERY
  // ============================================================

  Widget _buildUploadRecoveryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.restore_outlined,
                  size: 30,
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Upload Recovery',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(
                            width: 10,
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: const Text(
                              'Recovery UI v2',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      Text(
                        _incompleteJournals.isEmpty
                            ? 'No incomplete uploads.'
                            : '${_incompleteJournals.length} incomplete upload'
                                '${_incompleteJournals.length == 1 ? '' : 's'} found.',
                      ),
                    ],
                  ),
                ),
                if (_isLoadingJournals)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
              ],
            ),
            const SizedBox(
              height: 16,
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _isLoadingJournals
                      ? null
                      : () => _loadIncompleteJournals(
                            showStatus: true,
                          ),
                  icon: const Icon(
                    Icons.refresh,
                  ),
                  label: const Text(
                    'Refresh Journals',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _openJournalFolder,
                  icon: const Icon(
                    Icons.folder_open_outlined,
                  ),
                  label: const Text(
                    'Open Journal Folder',
                  ),
                ),
              ],
            ),
            if (_journalError != null) ...[
              const SizedBox(
                height: 14,
              ),
              Text(
                _journalError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            if (_incompleteJournals.isNotEmpty) ...[
              const SizedBox(
                height: 20,
              ),
              const Divider(),
              const SizedBox(
                height: 4,
              ),
              ..._incompleteJournals.map(
                _buildIncompleteJournalTile,
              ),
            ] else if (!_isLoadingJournals) ...[
              const SizedBox(
                height: 18,
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(
                  16,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(
                    12,
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                    ),
                    SizedBox(
                      width: 10,
                    ),
                    Text(
                      'No incomplete uploads.',
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(
              height: 14,
            ),
            Text(
              'Resume uses the local package recovery descriptor and the journal. '
              'Repair and Clean remain disabled for now.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncompleteJournalTile(
    TelegramStorageUploadJournal journal,
  ) {
    final fileMessageCount =
        _publishedFileMessageCount(journal);

    final hasRecoveryDescriptor =
        _packageRecoveryService
            .hasRecoveryDescriptor(
      journal,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 8,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(
          16,
        ),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant,
          ),
          borderRadius: BorderRadius.circular(
            12,
          ),
        ),
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
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      SelectableText(
                        journal.packageId,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  width: 12,
                ),
                Chip(
                  label: Text(
                    _journalStatusLabel(
                      journal.status,
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(
              height: 14,
            ),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                Text(
                  'Gallery: ${journal.galleryMessageIds.length} message(s)',
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
              height: 12,
            ),
            Text(
              'Catalog: ${journal.catalogChannel.title} '
              '(ID ${journal.catalogChannel.id})',
            ),
            Text(
              'Files: ${journal.filesChannel.title} '
              '(ID ${journal.filesChannel.id})',
            ),
            Text(
              'Updated: ${_formatJournalDate(journal.updatedAt)}',
            ),
            const SizedBox(
              height: 8,
            ),
            FutureBuilder<bool>(
              future: Directory(
                journal.stagingDirectoryPath,
              ).exists(),
              builder: (context, snapshot) {
                final exists = snapshot.data;

                final text = exists == null
                    ? 'Staging: checking...'
                    : exists
                        ? 'Staging: available locally'
                        : 'Staging: missing locally';

                return Row(
                  children: [
                    Icon(
                      exists == false
                          ? Icons.folder_off_outlined
                          : Icons.folder_outlined,
                      size: 18,
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    Expanded(
                      child: Text(
                        text,
                      ),
                    ),
                  ],
                );
              },
            ),
            if (journal.lastError != null &&
                journal.lastError!.trim().isNotEmpty) ...[
              const SizedBox(
                height: 12,
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(
                  12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .errorContainer,
                  borderRadius: BorderRadius.circular(
                    10,
                  ),
                ),
                child: Text(
                  journal.lastError!,
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(
              height: 14,
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _isBusy ||
                          journal.isRemoving ||
                          !hasRecoveryDescriptor
                      ? null
                      : () => _resumeJournal(
                            journal,
                          ),
                  icon: const Icon(
                    Icons.play_arrow_outlined,
                  ),
                  label: const Text(
                    'Resume',
                  ),
                ),
                if (hasRecoveryDescriptor)
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      Icons.save_outlined,
                      size: 16,
                    ),
                    label: Text(
                      'Recovery package available',
                    ),
                  )
                else
                  Text(
                    'Resume unavailable: no recovery descriptor.',
                    style: Theme.of(context)
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

  // ============================================================
  // WORKSPACE CHANNELS
  // ============================================================

  Widget _buildWorkspaceCard() {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(
          20,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.account_tree_outlined,
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
                      const Text(
                        'Storage Workspace',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      Text(
                        _workspace.isFullyConfigured
                            ? 'Catalog and Files channels are configured.'
                            : 'Configure the channels independently.',
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                    _workspace.isFullyConfigured
                        ? 'Ready'
                        : '$_configuredChannelCount / 2',
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 20,
            ),
            _buildChannelSection(
              role:
                  _TelegramStorageChannelRole.catalog,
              icon:
                  Icons.photo_library_outlined,
            ),
            const Divider(
              height: 36,
            ),
            _buildChannelSection(
              role:
                  _TelegramStorageChannelRole.files,
              icon:
                  Icons.inventory_2_outlined,
            ),
            const SizedBox(
              height: 16,
            ),
            Text(
              'The legacy single storage channel is migrated '
              'to Files Channel automatically. Catalog Channel '
              'is configured separately.',
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

  Widget _buildChannelSection({
    required _TelegramStorageChannelRole role,
    required IconData icon,
  }) {
    final channel =
        _channelForRole(role);

    final title =
        _channelRoleTitle(role);

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 28,
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
                    title.toUpperCase(),
                    style:
                        const TextStyle(
                      fontSize: 15,
                      fontWeight:
                          FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(
                    height: 4,
                  ),
                  Text(
                    _channelRoleDescription(
                      role,
                    ),
                  ),
                  if (channel != null) ...[
                    const SizedBox(
                      height: 10,
                    ),
                    Row(
                      children: [
                        const Icon(
                          Icons.cloud_done_outlined,
                          size: 18,
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Expanded(
                          child: Text(
                            '${channel.title} • ID ${channel.id}',
                            maxLines: 1,
                            overflow:
                                TextOverflow.ellipsis,
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        const Chip(
                          label: Text(
                            'Configured',
                          ),
                          visualDensity:
                              VisualDensity.compact,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(
          height: 14,
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed:
                  _isBusy
                      ? null
                      : () =>
                          _selectExistingChannel(
                            role,
                          ),
              icon: const Icon(
                Icons.cloud_queue,
              ),
              label: const Text(
                'Select Existing',
              ),
            ),
            FilledButton.icon(
              onPressed:
                  _isBusy
                      ? null
                      : () =>
                          _createWorkspaceChannel(
                            role,
                          ),
              icon: const Icon(
                Icons.add,
              ),
              label: const Text(
                'Create',
              ),
            ),
            if (channel != null)
              TextButton.icon(
                onPressed:
                    _isBusy
                        ? null
                        : () =>
                            _forgetWorkspaceChannel(
                              role,
                            ),
                icon: const Icon(
                  Icons.link_off,
                ),
                label: const Text(
                  'Forget',
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilesOperationsCard(
    TelegramStorageChannel channel,
  ) {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(
          20,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.cloud_done_outlined,
                  size: 32,
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current Files Storage',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      Text(
                        channel.title,
                      ),
                      Text(
                        'Channel ID: ${channel.id}',
                      ),
                    ],
                  ),
                ),
                const Chip(
                  label: Text(
                    'Files Channel',
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 20,
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed:
                      _isBusy
                          ? null
                          : _pickAndPrepareFolder,
                  icon: const Icon(
                    Icons.inventory_2_outlined,
                  ),
                  label: const Text(
                    'Prepare Model Folder',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _isBusy
                          ? null
                          : _pickAndUpload,
                  icon: const Icon(
                    Icons.cloud_upload_outlined,
                  ),
                  label: const Text(
                    'Upload Test File',
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 12,
            ),
            Text(
              'ZIP parts and manifests use this Files Channel. '
              'Gallery images are published separately to the '
              'configured Catalog Channel.',
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

  // ============================================================
  // PACKAGING
  // ============================================================

  Widget _buildPackagingProgress() {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(
          20,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              _packageStage,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 14,
            ),
            LinearProgressIndicator(
              value:
                  _packageProgress,
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              '${(_packageProgress * 100).toStringAsFixed(0)}%',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreparedPackageCard(
    TelegramStoragePackage package,
  ) {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(
          20,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: Text(
                    package.sourceFolderName,
                    style:
                        const TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 16,
            ),
            Text(
              'Original folder: '
              '${_formatSize(package.sourceSize)}',
            ),
            Text(
              'ZIP size: '
              '${_formatSize(package.archiveSize)}',
            ),
            Text(
              'Storage parts: '
              '${package.partCount}',
            ),
            Text(
              'Upload size: '
              '${_formatSize(package.totalUploadSize)}',
            ),
            const SizedBox(
              height: 16,
            ),
            const Divider(),
            ...package.parts.map(
              (part) {
                final uploadedId =
                    _lastPackageUpload
                        ?.partMessageIds[
                      part.index
                    ];

                return ListTile(
                  contentPadding:
                      EdgeInsets.zero,
                  leading:
                      CircleAvatar(
                    child: Text(
                      '${part.index}',
                    ),
                  ),
                  title: Text(
                    part.fileName,
                  ),
                  subtitle: Text(
                    uploadedId == null
                        ? '${_formatSize(part.size)} • '
                            '${part.sha256.substring(0, 12)}…'
                        : '${_formatSize(part.size)} • '
                            'Telegram message $uploadedId',
                  ),
                  trailing:
                      uploadedId != null
                          ? const Icon(
                              Icons.cloud_done_outlined,
                            )
                          : null,
                );
              },
            ),
            const SizedBox(
              height: 16,
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed:
                      _isBusy ||
                              !_workspace
                                  .isFullyConfigured
                          ? null
                          : _uploadPreparedPackage,
                  icon: const Icon(
                    Icons.cloud_upload_outlined,
                  ),
                  label: const Text(
                    'Upload Package to Telegram',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _openPreparedPackage,
                  icon: const Icon(
                    Icons.folder_open,
                  ),
                  label: const Text(
                    'Open Package Folder',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _isBusy
                          ? null
                          : _deletePreparedPackage,
                  icon: const Icon(
                    Icons.delete_outline,
                  ),
                  label: const Text(
                    'Delete Temporary Package',
                  ),
                ),
              ],
            ),
            if (!_workspace.isFullyConfigured) ...[
              const SizedBox(
                height: 12,
              ),
              const Text(
                'Configure both Catalog Channel and Files '
                'Channel before uploading this prepared package.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // PACKAGE UPLOAD
  // ============================================================

  Widget _buildPackageUploadProgress() {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(
          20,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'Uploading Storage Package',
              style:
                  TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 12,
            ),
            Text(
              _packageUploadStage,
            ),
            if (_packageUploadFileName !=
                null) ...[
              const SizedBox(
                height: 4,
              ),
              Text(
                _packageUploadFileName!,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    Theme.of(context)
                        .textTheme
                        .bodySmall,
              ),
            ],
            const SizedBox(
              height: 14,
            ),
            LinearProgressIndicator(
              value:
                  _packageUploadProgress,
            ),
            const SizedBox(
              height: 8,
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
      child: Padding(
        padding:
            const EdgeInsets.all(
          20,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.cloud_done_outlined,
                ),
                SizedBox(
                  width: 10,
                ),
                Text(
                  'Stored in Telegram',
                  style:
                      TextStyle(
                    fontSize: 18,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 14,
            ),
            Text(
              'Catalog Channel: ${result.catalogChannelTitle}',
            ),
            Text(
              'Files Channel: ${result.filesChannelTitle}',
            ),
            Text(
              'Gallery messages: ${result.galleryMessageIds.length}',
            ),
            Text(
              'Parts: ${result.partMessageIds.length}',
            ),
            Text(
              'Uploaded now: ${result.uploadedPartsNow}',
            ),
            Text(
              'Reused: ${result.reusedParts}',
            ),
            Text(
              'Manifest message ID: '
              '${result.manifestMessageId}',
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              result.alreadyUploaded
                  ? 'The previous completed upload '
                      'was detected locally.'
                  : 'A local upload receipt was created.',
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

  // ============================================================
  // TEST UPLOAD PROGRESS
  // ============================================================

  Widget _buildUploadProgress() {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(
          20,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              _currentFileName ??
                  'Uploading...',
            ),
            const SizedBox(
              height: 12,
            ),
            LinearProgressIndicator(
              value:
                  _uploadProgress,
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              '${(_uploadProgress * 100).toStringAsFixed(0)}%',
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // STATUS
  // ============================================================

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(
          16,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline,
            ),
            const SizedBox(
              width: 12,
            ),
            Expanded(
              child: Text(
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
      child: Padding(
        padding:
            const EdgeInsets.all(
          16,
        ),
        child: Row(
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
              width: 12,
            ),
            Expanded(
              child: Text(
                _error!,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseCard() {
    return const Card(
      child: Padding(
        padding:
            EdgeInsets.all(
          20,
        ),
        child: Text(
          'Telegram Storage V3\n\n'
          '✓ Separate Catalog Channel configuration\n'
          '✓ Separate Files Channel configuration\n'
          '✓ Legacy channel migration to Files Channel\n'
          '✓ Persistent Storage V3 workspace\n'
          '✓ Persistent upload journal model/service\n'
          '✓ Storage V3 uploader uses workspace\n'
          '✓ Publish Gallery to Catalog Channel\n'
          '✓ Persist Gallery message IDs/grouped ID\n'
          '✓ Persist each Files group immediately\n'
          '✓ Upload final manifest to Files Channel\n'
          '✓ Mark uploads STORED / FAILED\n'
          '✓ List incomplete uploads from journal\n'
          '○ Update Gallery post after file upload\n'
          '○ Resume / Repair / Clean',
        ),
      ),
    );
  }

  // ============================================================
  // SIZE
  // ============================================================

  String _formatSize(
    int bytes,
  ) {
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
