import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/telegram_storage_channel.dart';
import '../models/telegram_storage_package.dart';
import '../services/telegram_storage_packager.dart';
import '../services/telegram_storage_service.dart';

class TelegramStoragePage
    extends StatefulWidget {
  const TelegramStoragePage({
    super.key,
  });

  @override
  State<TelegramStoragePage>
      createState() =>
          _TelegramStoragePageState();
}

class _TelegramStoragePageState
    extends State<TelegramStoragePage> {
  final TelegramStorageService _storage =
      TelegramStorageService.instance;

  final TelegramStoragePackager _packager =
      TelegramStoragePackager.instance;

  TelegramStorageChannel? _channel;

  TelegramStoragePackage? _preparedPackage;

  bool _isLoading =
      true;

  bool _isCreatingChannel =
      false;

  bool _isLoadingChannels =
      false;

  bool _isUploading =
      false;

  bool _isPackaging =
      false;

  double _uploadProgress =
      0;

  double _packageProgress =
      0;

  String _packageStage =
      '';

  String? _error;

  String? _status;

  String? _currentFileName;

  bool get _isBusy =>
      _isCreatingChannel ||
      _isLoadingChannels ||
      _isUploading ||
      _isPackaging;

  @override
  void initState() {
    super.initState();

    _loadStorage();
  }

  Future<void> _loadStorage() async {
    final channel =
        await _storage.loadChannel();

    if (!mounted) {
      return;
    }

    setState(() {
      _channel =
          channel;

      _isLoading =
          false;
    });
  }

  // ============================================================
  // CREATE CHANNEL
  // ============================================================

  Future<void> _createChannel() async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isCreatingChannel =
          true;

      _error =
          null;

      _status =
          'Creating private Telegram storage channel...';
    });

    try {
      final channel =
          await _storage
              .createStorageChannel();

      if (!mounted) {
        return;
      }

      setState(() {
        _channel =
            channel;

        _status =
            'Storage channel created successfully.';

        _isCreatingChannel =
            false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error =
            e.toString();

        _status =
            null;

        _isCreatingChannel =
            false;
      });
    }
  }

  // ============================================================
  // EXISTING CHANNEL
  // ============================================================

  Future<void>
      _selectExistingChannel() async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isLoadingChannels =
          true;

      _error =
          null;

      _status =
          'Loading private Telegram channels...';
    });

    try {
      final channels =
          await _storage
              .listAvailableChannels();

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingChannels =
            false;

        _status =
            null;
      });

      if (channels.isEmpty) {
        setState(() {
          _error =
              'No writable private Telegram channels '
              'were found in the recent dialog list.';
        });

        return;
      }

      final selected =
          await showDialog<
              TelegramStorageChannel>(
        context:
            context,
        builder:
            (
          context,
        ) {
          return AlertDialog(
            title:
                const Text(
              'Select Storage Channel',
            ),
            content:
                SizedBox(
              width:
                  560,
              height:
                  420,
              child:
                  Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose a private channel where '
                    'this Telegram account can publish files.',
                    style:
                        Theme.of(context)
                            .textTheme
                            .bodyMedium,
                  ),
                  const SizedBox(
                    height:
                        16,
                  ),
                  Expanded(
                    child:
                        ListView.separated(
                      itemCount:
                          channels.length,
                      separatorBuilder:
                          (
                        context,
                        index,
                      ) =>
                              const Divider(
                        height:
                            1,
                      ),
                      itemBuilder:
                          (
                        context,
                        index,
                      ) {
                        final channel =
                            channels[
                                index];

                        return ListTile(
                          leading:
                              const CircleAvatar(
                            child:
                                Icon(
                              Icons.lock_outline,
                            ),
                          ),
                          title:
                              Text(
                            channel.title,
                          ),
                          subtitle:
                              Text(
                            'Private channel • ID ${channel.id}',
                          ),
                          trailing:
                              const Icon(
                            Icons.chevron_right,
                          ),
                          onTap:
                              () {
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
                onPressed:
                    () {
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

      await _storage
          .selectExistingChannel(
        selected,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _channel =
            selected;

        _error =
            null;

        _status =
            'Using "${selected.title}" '
            'as Fabularium Storage.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingChannels =
            false;

        _status =
            null;

        _error =
            e.toString();
      });
    }
  }

  // ============================================================
  // TEST UPLOAD
  // ============================================================

  Future<void> _pickAndUpload() async {
    final channel =
        _channel;

    if (channel == null ||
        _isBusy) {
      return;
    }

    final selection =
        await FilePicker.platform
            .pickFiles(
      allowMultiple:
          false,
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
      _isUploading =
          true;

      _uploadProgress =
          0;

      _currentFileName =
          selected.name;

      _error =
          null;

      _status =
          'Uploading ${selected.name}...';
    });

    try {
      final result =
          await _storage.uploadFile(
        channel:
            channel,
        filePath:
            path,
        onProgress:
            (
          progress,
        ) {
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
        _isUploading =
            false;

        _uploadProgress =
            1;

        _status =
            result.messageId != null
                ? '${result.fileName} uploaded successfully. '
                    'Telegram message ID: ${result.messageId}.'
                : '${result.fileName} uploaded successfully.';

        _currentFileName =
            null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isUploading =
            false;

        _error =
            e.toString();

        _status =
            null;

        _currentFileName =
            null;
      });
    }
  }

  // ============================================================
  // PREPARE MODEL FOLDER
  // ============================================================

  Future<void>
      _pickAndPrepareFolder() async {
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
      _isPackaging =
          true;

      _packageProgress =
          0;

      _packageStage =
          'Preparing...';

      _preparedPackage =
          null;

      _error =
          null;

      _status =
          null;
    });

    try {
      final package =
          await _packager.prepareFolder(
        folderPath:
            folderPath,
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

      if (!mounted) {
        return;
      }

      setState(() {
        _preparedPackage =
            package;

        _packageProgress =
            1;

        _packageStage =
            'Package ready.';

        _isPackaging =
            false;

        _status =
            package.isSplit
                ? 'Package prepared successfully '
                    'in ${package.partCount} parts.'
                : 'Package prepared successfully '
                    'as a single ZIP.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isPackaging =
            false;

        _packageProgress =
            0;

        _packageStage =
            '';

        _error =
            e.toString();
      });
    }
  }

  Future<void> _openPreparedPackage() async {
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
        _error =
            e.toString();
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
      context:
          context,
      builder:
          (
        context,
      ) {
        return AlertDialog(
          title:
              const Text(
            'Delete Prepared Package?',
          ),
          content:
              const Text(
            'The temporary ZIP, parts and manifest '
            'will be deleted. The original model '
            'folder will not be changed.',
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
            FilledButton(
              onPressed:
                  () {
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
        _preparedPackage =
            null;

        _status =
            'Prepared package deleted.';
      });
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

  // ============================================================
  // FORGET CHANNEL
  // ============================================================

  Future<void> _forgetStorage() async {
    if (_isBusy) {
      return;
    }

    final confirmed =
        await showDialog<bool>(
      context:
          context,
      builder:
          (
        context,
      ) {
        return AlertDialog(
          title:
              const Text(
            'Forget Storage Channel?',
          ),
          content:
              const Text(
            'This removes only the local '
            'configuration. Nothing will be '
            'deleted from Telegram.',
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
            FilledButton(
              onPressed:
                  () {
                Navigator.of(
                  context,
                ).pop(
                  true,
                );
              },
              child:
                  const Text(
                'Forget',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await _storage.clearChannel();

    if (!mounted) {
      return;
    }

    setState(() {
      _channel =
          null;

      _status =
          null;

      _error =
          null;

      _uploadProgress =
          0;
    });
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar:
          AppBar(
        title:
            const Text(
          'Telegram Storage',
        ),
      ),
      body:
          _buildBody(),
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
          'Fabularium Cloud Storage',
          style:
              Theme.of(context)
                  .textTheme
                  .headlineSmall,
        ),

        const SizedBox(
          height:
              8,
        ),

        const Text(
          'Package model folders and store them '
          'inside your private Telegram channel.',
        ),

        const SizedBox(
          height:
              24,
        ),

        if (_channel == null)
          _buildUnconfiguredCard()
        else
          _buildConfiguredCard(
            _channel!,
          ),

        if (_isPackaging) ...[
          const SizedBox(
            height:
                20,
          ),
          _buildPackagingProgress(),
        ],

        if (_preparedPackage != null) ...[
          const SizedBox(
            height:
                20,
          ),
          _buildPreparedPackageCard(
            _preparedPackage!,
          ),
        ],

        if (_isUploading) ...[
          const SizedBox(
            height:
                20,
          ),
          _buildUploadProgress(),
        ],

        if (_status != null) ...[
          const SizedBox(
            height:
                20,
          ),
          _buildStatusCard(),
        ],

        if (_error != null) ...[
          const SizedBox(
            height:
                20,
          ),
          _buildErrorCard(),
        ],

        const SizedBox(
          height:
              24,
        ),

        _buildPhaseCard(),
      ],
    );
  }

  Widget _buildUnconfiguredCard() {
    return Card(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          20,
        ),
        child:
            Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'Storage is not configured',
              style:
                  TextStyle(
                fontSize:
                    18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            const SizedBox(
              height:
                  16,
            ),
            Wrap(
              spacing:
                  12,
              runSpacing:
                  12,
              children: [
                FilledButton.icon(
                  onPressed:
                      _isBusy
                          ? null
                          : _createChannel,
                  icon:
                      const Icon(
                    Icons.add,
                  ),
                  label:
                      const Text(
                    'Create New Storage Channel',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _isBusy
                          ? null
                          : _selectExistingChannel,
                  icon:
                      const Icon(
                    Icons.cloud_queue,
                  ),
                  label:
                      const Text(
                    'Use Existing Telegram Channel',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfiguredCard(
    TelegramStorageChannel channel,
  ) {
    return Card(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          20,
        ),
        child:
            Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.cloud_done_outlined,
                  size:
                      32,
                ),
                const SizedBox(
                  width:
                      12,
                ),
                Expanded(
                  child:
                      Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.title,
                        style:
                            const TextStyle(
                          fontSize:
                              18,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Channel ID: ${channel.id}',
                      ),
                    ],
                  ),
                ),
                const Chip(
                  label:
                      Text(
                    'Configured',
                  ),
                ),
              ],
            ),

            const SizedBox(
              height:
                  20,
            ),

            Wrap(
              spacing:
                  12,
              runSpacing:
                  12,
              children: [
                FilledButton.icon(
                  onPressed:
                      _isBusy
                          ? null
                          : _pickAndPrepareFolder,
                  icon:
                      const Icon(
                    Icons.inventory_2_outlined,
                  ),
                  label:
                      const Text(
                    'Prepare Model Folder',
                  ),
                ),

                OutlinedButton.icon(
                  onPressed:
                      _isBusy
                          ? null
                          : _pickAndUpload,
                  icon:
                      const Icon(
                    Icons.cloud_upload_outlined,
                  ),
                  label:
                      const Text(
                    'Upload Test File',
                  ),
                ),

                OutlinedButton.icon(
                  onPressed:
                      _isBusy
                          ? null
                          : _selectExistingChannel,
                  icon:
                      const Icon(
                    Icons.swap_horiz,
                  ),
                  label:
                      const Text(
                    'Change Channel',
                  ),
                ),

                TextButton.icon(
                  onPressed:
                      _isBusy
                          ? null
                          : _forgetStorage,
                  icon:
                      const Icon(
                    Icons.link_off,
                  ),
                  label:
                      const Text(
                    'Forget Configuration',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackagingProgress() {
    return Card(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          20,
        ),
        child:
            Column(
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
              height:
                  14,
            ),
            LinearProgressIndicator(
              value:
                  _packageProgress,
            ),
            const SizedBox(
              height:
                  8,
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
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          20,
        ),
        child:
            Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                ),
                SizedBox(
                  width:
                      10,
                ),
                Text(
                  'Prepared Storage Package',
                  style:
                      TextStyle(
                    fontSize:
                        18,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(
              height:
                  16,
            ),

            Text(
              package.sourceFolderName,
              style:
                  Theme.of(context)
                      .textTheme
                      .titleMedium,
            ),

            const SizedBox(
              height:
                  8,
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
              package.isSplit
                  ? 'Archive was split because it exceeded 1900 MB.'
                  : 'Archive fits in a single Telegram file.',
            ),

            const SizedBox(
              height:
                  16,
            ),

            const Divider(),

            const SizedBox(
              height:
                  8,
            ),

            ...package.parts.map(
              (
                part,
              ) {
                final shortHash =
                    part.sha256.length >=
                            16
                        ? part.sha256.substring(
                            0,
                            16,
                          )
                        : part.sha256;

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical:
                        6,
                  ),
                  child:
                      Row(
                    children: [
                      CircleAvatar(
                        radius:
                            14,
                        child:
                            Text(
                          '${part.index}',
                          style:
                              const TextStyle(
                            fontSize:
                                11,
                          ),
                        ),
                      ),
                      const SizedBox(
                        width:
                            10,
                      ),
                      Expanded(
                        child:
                            Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              part.fileName,
                              overflow:
                                  TextOverflow.ellipsis,
                            ),
                            Text(
                              '${_formatSize(part.size)} '
                              '• SHA-256 $shortHash…',
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
                );
              },
            ),

            const SizedBox(
              height:
                  12,
            ),

            Text(
              'Manifest: '
              '${package.manifestPath.split(RegExp(r'[\\/]+')).last}',
              style:
                  Theme.of(context)
                      .textTheme
                      .bodySmall,
            ),

            const SizedBox(
              height:
                  18,
            ),

            Wrap(
              spacing:
                  12,
              runSpacing:
                  12,
              children: [
                FilledButton.icon(
                  onPressed:
                      _openPreparedPackage,
                  icon:
                      const Icon(
                    Icons.folder_open,
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
                    'Delete Temporary Package',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadProgress() {
    return Card(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          20,
        ),
        child:
            Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              _currentFileName ??
                  'Uploading...',
            ),
            const SizedBox(
              height:
                  12,
            ),
            LinearProgressIndicator(
              value:
                  _uploadProgress,
            ),
            const SizedBox(
              height:
                  8,
            ),
            Text(
              '${(_uploadProgress * 100).toStringAsFixed(0)}%',
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
          16,
        ),
        child:
            Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
            ),
            const SizedBox(
              width:
                  12,
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
          16,
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
                  12,
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

  Widget _buildPhaseCard() {
    return const Card(
      child:
          Padding(
        padding:
            EdgeInsets.all(
          20,
        ),
        child:
            Text(
          'Storage Phase 2\n\n'
          '✓ Select existing private channel\n'
          '✓ Real MTProto upload\n'
          '✓ Select model folder\n'
          '✓ ZIP model folder\n'
          '✓ SHA-256 integrity checks\n'
          '✓ Split archives above 1900 MB\n'
          '✓ Manifest JSON\n'
          '○ Upload complete package\n'
          '○ Manifest with Telegram message IDs\n'
          '○ Restore package from Telegram',
        ),
      ),
    );
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