import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/telegram_storage_channel.dart';
import '../models/telegram_storage_package.dart';
import '../models/telegram_storage_upload_journal.dart';
import '../models/telegram_storage_workspace.dart';
import '../services/telegram_storage_packager.dart';
import '../services/telegram_storage_service.dart';
import '../services/telegram_storage_upload_journal_service.dart';
import '../services/telegram_storage_workspace_service.dart';

class TelegramStoragePage extends StatefulWidget {
  const TelegramStoragePage({
    super.key,
  });

  @override
  State<TelegramStoragePage> createState() =>
      _TelegramStoragePageState();
}

enum _StorageChannelRole {
  catalog,
  files,
}

class _TelegramStoragePageState
    extends State<TelegramStoragePage> {
  final TelegramStorageWorkspaceService _workspaceService =
      TelegramStorageWorkspaceService.instance;

  final TelegramStorageService _storage =
      TelegramStorageService.instance;

  final TelegramStoragePackager _packager =
      TelegramStoragePackager.instance;

  final TelegramStorageUploadJournalService _journalService =
      TelegramStorageUploadJournalService.instance;

  TelegramStorageWorkspace _workspace =
      const TelegramStorageWorkspace.empty();

  TelegramStoragePackage? _preparedPackage;

  List<TelegramStorageUploadJournal> _incompleteUploads =
      <TelegramStorageUploadJournal>[];

  bool _isLoading = true;

  bool _isLoadingChannels = false;

  bool _isCreatingChannel = false;

  bool _isPackaging = false;

  bool _isUploadingTestFile = false;

  double _packageProgress = 0;

  double _testUploadProgress = 0;

  String _packageStage = '';

  String? _testUploadFileName;

  String? _status;

  String? _error;

  bool get _isBusy =>
      _isLoadingChannels ||
      _isCreatingChannel ||
      _isPackaging ||
      _isUploadingTestFile;

  @override
  void initState() {
    super.initState();

    _load();
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> _load() async {
    try {
      final workspace =
          await _workspaceService.load();

      final incomplete =
          await _journalService.listIncomplete();

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace = workspace;

        _incompleteUploads = incomplete;

        _isLoading = false;
      });
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

  Future<void> _reloadJournals() async {
    final incomplete =
        await _journalService.listIncomplete();

    if (!mounted) {
      return;
    }

    setState(() {
      _incompleteUploads = incomplete;
    });
  }

  // ============================================================
  // SELECT EXISTING CHANNEL
  // ============================================================

  Future<void> _selectExistingChannel(
    _StorageChannelRole role,
  ) async {
    if (_isBusy) {
      return;
    }

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

      setState(() {
        _isLoadingChannels = false;

        _status = null;
      });

      if (channels.isEmpty) {
        setState(() {
          _error =
              'No writable private Telegram channels '
              'were found.';
        });

        return;
      }

      final unavailableChannelId =
          role == _StorageChannelRole.catalog
              ? _workspace.filesChannel?.id
              : _workspace.catalogChannel?.id;

      final availableChannels =
          channels
              .where(
                (
                  channel,
                ) =>
                    channel.id !=
                    unavailableChannelId,
              )
              .toList();

      if (availableChannels.isEmpty) {
        setState(() {
          _error =
              'No other private channel is available. '
              'Catalog Channel and Files Channel must '
              'be different.';
        });

        return;
      }

      final selected =
          await showDialog<
              TelegramStorageChannel>(
        context: context,
        builder: (
          context,
        ) {
          return AlertDialog(
            title: Text(
              role ==
                      _StorageChannelRole.catalog
                  ? 'Select Catalog Channel'
                  : 'Select Files Channel',
            ),
            content: SizedBox(
              width: 580,
              height: 440,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    role ==
                            _StorageChannelRole.catalog
                        ? 'Choose the private channel '
                            'that will contain model images '
                            'and catalog information.'
                        : 'Choose the private channel '
                            'that will contain ZIP files, '
                            'package parts and manifests.',
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount:
                          availableChannels.length,
                      separatorBuilder: (
                        context,
                        index,
                      ) =>
                          const Divider(
                        height: 1,
                      ),
                      itemBuilder: (
                        context,
                        index,
                      ) {
                        final channel =
                            availableChannels[index];

                        return ListTile(
                          leading:
                              CircleAvatar(
                            child: Icon(
                              role ==
                                      _StorageChannelRole
                                          .catalog
                                  ? Icons
                                      .photo_library_outlined
                                  : Icons
                                      .folder_zip_outlined,
                            ),
                          ),
                          title: Text(
                            channel.title,
                          ),
                          subtitle: Text(
                            'Private channel • '
                            'ID ${channel.id}',
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
                child:
                    const Text(
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

      final TelegramStorageWorkspace updated;

      if (role ==
          _StorageChannelRole.catalog) {
        updated =
            await _workspaceService
                .selectCatalogChannel(
          selected,
        );
      } else {
        updated =
            await _workspaceService
                .selectFilesChannel(
          selected,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace = updated;

        _error = null;

        _status =
            role ==
                    _StorageChannelRole.catalog
                ? '"${selected.title}" is now '
                    'the Catalog Channel.'
                : '"${selected.title}" is now '
                    'the Files Channel.';
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

  // ============================================================
  // CREATE CHANNEL
  // ============================================================

  Future<void> _createChannel(
    _StorageChannelRole role,
  ) async {
    if (_isBusy) {
      return;
    }

    final channelName =
        role == _StorageChannelRole.catalog
            ? TelegramStorageWorkspaceService
                .defaultCatalogChannelTitle
            : TelegramStorageWorkspaceService
                .defaultFilesChannelTitle;

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (
        context,
      ) {
        return AlertDialog(
          title: const Text(
            'Create Private Channel?',
          ),
          content: Text(
            'Fabularium will create the private '
            'Telegram channel:\n\n'
            '$channelName',
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
              child:
                  const Text(
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
              icon:
                  const Icon(
                Icons.add,
              ),
              label:
                  const Text(
                'Create',
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
      _isCreatingChannel = true;

      _error = null;

      _status =
          'Creating $channelName...';
    });

    try {
      final TelegramStorageWorkspace updated;

      if (role ==
          _StorageChannelRole.catalog) {
        updated =
            await _workspaceService
                .createCatalogChannel();
      } else {
        updated =
            await _workspaceService
                .createFilesChannel();
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace = updated;

        _isCreatingChannel = false;

        _status =
            '$channelName created successfully.';
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

  // ============================================================
  // CLEAR CHANNEL
  // ============================================================

  Future<void> _clearChannel(
    _StorageChannelRole role,
  ) async {
    if (_isBusy) {
      return;
    }

    final channel =
        role == _StorageChannelRole.catalog
            ? _workspace.catalogChannel
            : _workspace.filesChannel;

    if (channel == null) {
      return;
    }

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (
        context,
      ) {
        return AlertDialog(
          title: const Text(
            'Remove Channel Configuration?',
          ),
          content: Text(
            'Remove "${channel.title}" from '
            'Fabularium configuration?\n\n'
            'The Telegram channel itself will NOT '
            'be deleted.',
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
              child:
                  const Text(
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
              child:
                  const Text(
                'Remove',
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
      final TelegramStorageWorkspace updated;

      if (role ==
          _StorageChannelRole.catalog) {
        updated =
            await _workspaceService
                .clearCatalogChannel();
      } else {
        updated =
            await _workspaceService
                .clearFilesChannel();
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace = updated;

        _error = null;

        _status =
            'Channel configuration removed.';
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
  // TEST FILE UPLOAD
  // ============================================================

  Future<void> _testFilesChannel() async {
    final channel =
        _workspace.filesChannel;

    if (channel == null ||
        _isBusy) {
      return;
    }

    final selection =
        await FilePicker.platform.pickFiles(
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
      _isUploadingTestFile = true;

      _testUploadProgress = 0;

      _testUploadFileName =
          selected.name;

      _error = null;

      _status =
          'Uploading test file to '
          '${channel.title}...';
    });

    try {
      final result =
          await _storage.uploadFile(
        channel: channel,
        filePath: path,
        onProgress: (
          progress,
        ) {
          if (!mounted) {
            return;
          }

          setState(() {
            _testUploadProgress =
                progress;
          });
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isUploadingTestFile = false;

        _testUploadProgress = 1;

        _testUploadFileName = null;

        _status =
            result.messageId != null
                ? 'Files Channel test successful. '
                    'Message ID: '
                    '${result.messageId}.'
                : 'Files Channel test successful.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isUploadingTestFile = false;

        _testUploadFileName = null;

        _status = null;

        _error = e.toString();
      });
    }
  }

  // ============================================================
  // PREPARE PACKAGE
  // ============================================================

  Future<void> _preparePackage() async {
    if (_isBusy) {
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
          'Preparing package...';

      _preparedPackage = null;

      _error = null;

      _status = null;
    });

    try {
      final package =
          await _packager.prepareFolder(
        folderPath: folderPath,
        onProgress: (
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

      if (!mounted) {
        return;
      }

      setState(() {
        _preparedPackage =
            package;

        _isPackaging = false;

        _packageProgress = 1;

        _packageStage =
            'Package ready.';

        _status =
            package.isSplit
                ? 'Package prepared with '
                    '${package.partCount} parts.'
                : 'Package prepared as '
                    'a single ZIP.';
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
  // OPEN PACKAGE
  // ============================================================

  Future<void> _openPackageFolder() async {
    final package =
        _preparedPackage;

    if (package == null) {
      return;
    }

    try {
      await _packager.openPackageFolder(
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

  // ============================================================
  // DELETE PACKAGE
  // ============================================================

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
      builder: (
        context,
      ) {
        return AlertDialog(
          title: const Text(
            'Delete Prepared Package?',
          ),
          content: Text(
            'Delete the temporary package for '
            '"${package.displayName}"?\n\n'
            'The original model folder will not '
            'be modified.',
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
              child:
                  const Text(
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
              child:
                  const Text(
                'Delete',
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
      await _packager.deletePackage(
        package,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _preparedPackage = null;

        _packageProgress = 0;

        _packageStage = '';

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
  // JOURNAL FOLDER
  // ============================================================

  Future<void> _openJournalFolder() async {
    try {
      await _journalService
          .openJournalFolder();
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
        title:
            const Text(
          'Telegram Storage',
        ),
        actions: [
          IconButton(
            tooltip:
                'Refresh',
            onPressed:
                _isBusy
                    ? null
                    : _load,
            icon:
                const Icon(
              Icons.refresh,
            ),
          ),
          const SizedBox(
            width: 8,
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(
                  child:
                      CircularProgressIndicator(),
                )
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding:
          const EdgeInsets.all(
        24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(
            maxWidth: 1100,
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),

              const SizedBox(
                height: 24,
              ),

              _buildWorkspaceStatus(),

              const SizedBox(
                height: 20,
              ),

              _buildChannelCard(
                role:
                    _StorageChannelRole
                        .catalog,
                channel:
                    _workspace
                        .catalogChannel,
              ),

              const SizedBox(
                height: 16,
              ),

              _buildChannelCard(
                role:
                    _StorageChannelRole
                        .files,
                channel:
                    _workspace
                        .filesChannel,
              ),

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

              if (_isUploadingTestFile) ...[
                const SizedBox(
                  height: 20,
                ),
                _buildTestUploadProgress(),
              ],

              const SizedBox(
                height: 28,
              ),

              _buildPackageSection(),

              const SizedBox(
                height: 28,
              ),

              _buildMaintenanceSection(),

              const SizedBox(
                height: 32,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          'Fabularium Storage V3',
          style:
              Theme.of(context)
                  .textTheme
                  .headlineMedium,
        ),
        const SizedBox(
          height: 8,
        ),
        Text(
          'Use one private Telegram channel '
          'for the visual catalog and another '
          'private channel for model files.',
          style:
              Theme.of(context)
                  .textTheme
                  .bodyLarge,
        ),
      ],
    );
  }

  // ============================================================
  // WORKSPACE STATUS
  // ============================================================

  Widget _buildWorkspaceStatus() {
    final configured =
        _workspace.isFullyConfigured;

    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(
          20,
        ),
        child: Row(
          children: [
            CircleAvatar(
              child: Icon(
                configured
                    ? Icons
                        .cloud_done_outlined
                    : Icons
                        .cloud_off_outlined,
              ),
            ),
            const SizedBox(
              width: 16,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    configured
                        ? 'Storage workspace ready'
                        : 'Storage workspace incomplete',
                    style:
                        Theme.of(context)
                            .textTheme
                            .titleMedium,
                  ),
                  const SizedBox(
                    height: 4,
                  ),
                  Text(
                    configured
                        ? 'Catalog and Files channels '
                            'are configured.'
                        : 'Configure both Telegram '
                            'channels before enabling '
                            'the Storage V3 uploader.',
                  ),
                ],
              ),
            ),
            Icon(
              configured
                  ? Icons.check_circle
                  : Icons.info_outline,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CHANNEL CARD
  // ============================================================

  Widget _buildChannelCard({
    required _StorageChannelRole role,
    required TelegramStorageChannel? channel,
  }) {
    final isCatalog =
        role ==
        _StorageChannelRole.catalog;

    final title =
        isCatalog
            ? 'Catalog Channel'
            : 'Files Channel';

    final description =
        isCatalog
            ? 'Images, previews, model metadata '
                'and catalog entries.'
            : 'ZIP archives, package parts '
                'and manifests.';

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
                CircleAvatar(
                  child: Icon(
                    isCatalog
                        ? Icons
                            .photo_library_outlined
                        : Icons
                            .folder_zip_outlined,
                  ),
                ),
                const SizedBox(
                  width: 16,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style:
                            Theme.of(context)
                                .textTheme
                                .titleLarge,
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      Text(
                        description,
                      ),
                    ],
                  ),
                ),
                if (channel != null)
                  const Chip(
                    avatar:
                        Icon(
                      Icons.check,
                      size: 18,
                    ),
                    label:
                        Text(
                      'Configured',
                    ),
                  ),
              ],
            ),

            const SizedBox(
              height: 20,
            ),

            if (channel != null)
              Container(
                width:
                    double.infinity,
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                decoration:
                    BoxDecoration(
                  border:
                      Border.all(
                    color:
                        Theme.of(context)
                            .dividerColor,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_outline,
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
                            channel.title,
                            style:
                                Theme.of(context)
                                    .textTheme
                                    .titleMedium,
                          ),
                          const SizedBox(
                            height: 2,
                          ),
                          Text(
                            'Telegram channel ID: '
                            '${channel.id}',
                            style:
                                Theme.of(context)
                                    .textTheme
                                    .bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                width:
                    double.infinity,
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                decoration:
                    BoxDecoration(
                  border:
                      Border.all(
                    color:
                        Theme.of(context)
                            .dividerColor,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                ),
                child:
                    const Text(
                  'No channel configured.',
                ),
              ),

            const SizedBox(
              height: 16,
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
                  icon:
                      const Icon(
                    Icons.search,
                  ),
                  label:
                      const Text(
                    'Select Existing',
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      _isBusy
                          ? null
                          : () =>
                              _createChannel(
                                role,
                              ),
                  icon:
                      const Icon(
                    Icons.add,
                  ),
                  label:
                      const Text(
                    'Create Channel',
                  ),
                ),
                if (channel != null)
                  TextButton.icon(
                    onPressed:
                        _isBusy
                            ? null
                            : () =>
                                _clearChannel(
                                  role,
                                ),
                    icon:
                        const Icon(
                      Icons
                          .link_off_outlined,
                    ),
                    label:
                        const Text(
                      'Remove Configuration',
                    ),
                  ),
                if (!isCatalog &&
                    channel != null)
                  OutlinedButton.icon(
                    onPressed:
                        _isBusy
                            ? null
                            : _testFilesChannel,
                    icon:
                        const Icon(
                      Icons
                          .cloud_upload_outlined,
                    ),
                    label:
                        const Text(
                      'Test Upload',
                    ),
                  ),
              ],
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
            const Icon(
              Icons.error_outline,
            ),
            const SizedBox(
              width: 12,
            ),
            Expanded(
              child: Text(
                _error!,
              ),
            ),
            IconButton(
              tooltip:
                  'Dismiss',
              onPressed: () {
                setState(() {
                  _error = null;
                });
              },
              icon:
                  const Icon(
                Icons.close,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TEST PROGRESS
  // ============================================================

  Widget _buildTestUploadProgress() {
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
              _testUploadFileName ??
                  'Uploading test file...',
              style:
                  Theme.of(context)
                      .textTheme
                      .titleMedium,
            ),
            const SizedBox(
              height: 12,
            ),
            LinearProgressIndicator(
              value:
                  _testUploadProgress,
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              '${(_testUploadProgress * 100).toStringAsFixed(1)}%',
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // PACKAGE SECTION
  // ============================================================

  Widget _buildPackageSection() {
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
                  width: 12,
                ),
                Text(
                  'Model Package',
                  style:
                      Theme.of(context)
                          .textTheme
                          .titleLarge,
                ),
              ],
            ),

            const SizedBox(
              height: 8,
            ),

            const Text(
              'Prepare the model ZIP and gallery '
              'information locally before uploading.',
            ),

            const SizedBox(
              height: 20,
            ),

            if (_isPackaging) ...[
              LinearProgressIndicator(
                value:
                    _packageProgress,
              ),
              const SizedBox(
                height: 8,
              ),
              Text(
                _packageStage,
              ),
              const SizedBox(
                height: 20,
              ),
            ],

            if (_preparedPackage !=
                null)
              _buildPreparedPackage(),

            if (_preparedPackage ==
                null)
              FilledButton.icon(
                onPressed:
                    _isBusy
                        ? null
                        : _preparePackage,
                icon:
                    const Icon(
                  Icons
                      .create_new_folder_outlined,
                ),
                label:
                    const Text(
                  'Prepare Model Folder',
                ),
              ),

            if (_preparedPackage !=
                null) ...[
              const SizedBox(
                height: 16,
              ),

              Container(
                width:
                    double.infinity,
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                decoration:
                    BoxDecoration(
                  border:
                      Border.all(
                    color:
                        Theme.of(context)
                            .dividerColor,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                ),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons
                          .construction_outlined,
                    ),
                    const SizedBox(
                      width: 12,
                    ),
                    const Expanded(
                      child: Text(
                        'Storage V3 upload is temporarily '
                        'disabled on this screen while we '
                        'connect the new Catalog Channel + '
                        'Files Channel flow with Resume, '
                        'Repair and Clean. This prevents '
                        'accidentally uploading the package '
                        'using the old single-channel flow.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreparedPackage() {
    final package =
        _preparedPackage!;

    return Container(
      width:
          double.infinity,
      padding:
          const EdgeInsets.all(
        16,
      ),
      decoration:
          BoxDecoration(
        border:
            Border.all(
          color:
              Theme.of(context)
                  .dividerColor,
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
          Row(
            children: [
              const Icon(
                Icons
                    .folder_zip_outlined,
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
                      package.displayName,
                      style:
                          Theme.of(context)
                              .textTheme
                              .titleMedium,
                    ),
                    const SizedBox(
                      height: 4,
                    ),
                    Text(
                      'Package ID: '
                      '${package.packageId}',
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 16,
          ),

          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _buildPackageStat(
                'Archive',
                _formatSize(
                  package.archiveSize,
                ),
              ),
              _buildPackageStat(
                'Parts',
                package.partCount
                    .toString(),
              ),
              _buildPackageStat(
                'Gallery',
                '${package.galleryImageCount} images',
              ),
              _buildPackageStat(
                'Source',
                _formatSize(
                  package.sourceSize,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 16,
          ),

          if (package.parts.isNotEmpty)
            Column(
              children:
                  package.parts
                      .map(
                        (
                          part,
                        ) =>
                            ListTile(
                          contentPadding:
                              EdgeInsets.zero,
                          leading:
                              const Icon(
                            Icons
                                .insert_drive_file_outlined,
                          ),
                          title:
                              Text(
                            part.fileName,
                          ),
                          subtitle:
                              Text(
                            _formatSize(
                              part.size,
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),

          const Divider(),

          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed:
                    _openPackageFolder,
                icon:
                    const Icon(
                  Icons
                      .folder_open_outlined,
                ),
                label:
                    const Text(
                  'Open Package Folder',
                ),
              ),
              OutlinedButton.icon(
                onPressed:
                    _isBusy
                        ? null
                        : _deletePreparedPackage,
                icon:
                    const Icon(
                  Icons.delete_outline,
                ),
                label:
                    const Text(
                  'Delete Prepared Package',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPackageStat(
    String label,
    String value,
  ) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style:
                Theme.of(context)
                    .textTheme
                    .bodySmall,
          ),
          const SizedBox(
            height: 2,
          ),
          Text(
            value,
            style:
                Theme.of(context)
                    .textTheme
                    .titleMedium,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MAINTENANCE
  // ============================================================

  Widget _buildMaintenanceSection() {
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
                  Icons
                      .build_circle_outlined,
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Text(
                    'Storage Maintenance',
                    style:
                        Theme.of(context)
                            .textTheme
                            .titleLarge,
                  ),
                ),
                IconButton(
                  tooltip:
                      'Refresh journals',
                  onPressed:
                      _isBusy
                          ? null
                          : _reloadJournals,
                  icon:
                      const Icon(
                    Icons.refresh,
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 8,
            ),

            Text(
              _incompleteUploads.isEmpty
                  ? 'No incomplete Storage V3 uploads '
                      'were found.'
                  : '${_incompleteUploads.length} '
                      'incomplete upload'
                      '${_incompleteUploads.length == 1 ? '' : 's'} '
                      'found.',
            ),

            const SizedBox(
              height: 16,
            ),

            if (_incompleteUploads.isNotEmpty)
              Column(
                children:
                    _incompleteUploads
                        .map(
                          _buildJournalTile,
                        )
                        .toList(),
              ),

            const SizedBox(
              height: 12,
            ),

            OutlinedButton.icon(
              onPressed:
                  _openJournalFolder,
              icon:
                  const Icon(
                Icons
                    .folder_open_outlined,
              ),
              label:
                  const Text(
                'Open Journal Folder',
              ),
            ),

            if (_incompleteUploads.isNotEmpty) ...[
              const SizedBox(
                height: 12,
              ),
              const Text(
                'Resume, Repair and Clean actions '
                'will be connected in the next step.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildJournalTile(
    TelegramStorageUploadJournal journal,
  ) {
    return ListTile(
      contentPadding:
          EdgeInsets.zero,
      leading:
          CircleAvatar(
        child: Icon(
          _journalStatusIcon(
            journal.status,
          ),
        ),
      ),
      title:
          Text(
        journal.modelName.isEmpty
            ? journal.packageId
            : journal.modelName,
      ),
      subtitle:
          Text(
        '${journal.status.value.toUpperCase()}'
        ' • '
        '${journal.publishedFileGroupCount} '
        'published file group'
        '${journal.publishedFileGroupCount == 1 ? '' : 's'}'
        '${journal.lastError == null ? '' : '\n${journal.lastError}'}',
      ),
      isThreeLine:
          journal.lastError != null,
      trailing:
          Text(
        _formatDate(
          journal.updatedAt,
        ),
      ),
    );
  }

  IconData _journalStatusIcon(
    TelegramStorageUploadStatus status,
  ) {
    switch (status) {
      case TelegramStorageUploadStatus.preparing:
        return Icons
            .inventory_2_outlined;

      case TelegramStorageUploadStatus.uploading:
        return Icons
            .cloud_upload_outlined;

      case TelegramStorageUploadStatus.failed:
        return Icons
            .error_outline;

      case TelegramStorageUploadStatus.stored:
        return Icons
            .cloud_done_outlined;

      case TelegramStorageUploadStatus.removing:
        return Icons
            .delete_sweep_outlined;
    }
  }

  // ============================================================
  // FORMAT
  // ============================================================

  String _formatSize(
    int bytes,
  ) {
    const int kb =
        1024;

    const int mb =
        1024 * kb;

    const int gb =
        1024 * mb;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }

    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(2)} MB';
    }

    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(2)} KB';
    }

    return '$bytes B';
  }

  String _formatDate(
    DateTime value,
  ) {
    final local =
        value.toLocal();

    final day =
        local.day
            .toString()
            .padLeft(
              2,
              '0',
            );

    final month =
        local.month
            .toString()
            .padLeft(
              2,
              '0',
            );

    final hour =
        local.hour
            .toString()
            .padLeft(
              2,
              '0',
            );

    final minute =
        local.minute
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '$day/$month '
        '$hour:$minute';
  }
}