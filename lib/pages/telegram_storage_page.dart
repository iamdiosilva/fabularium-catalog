import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/telegram_storage_channel.dart';
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

  TelegramStorageChannel? _channel;

  bool _isLoading =
      true;

  bool _isCreatingChannel =
      false;

  bool _isLoadingChannels =
      false;

  bool _isUploading =
      false;

  double _uploadProgress =
      0;

  String? _error;

  String? _status;

  String? _currentFileName;

  bool get _isBusy =>
      _isCreatingChannel ||
      _isLoadingChannels ||
      _isUploading;

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
            'Using existing Telegram channel '
            '"${selected.title}" as Fabularium Storage.';
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
  // UPLOAD FILE
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
      if (!mounted) {
        return;
      }

      setState(() {
        _error =
            'Could not access the selected file.';
      });

      return;
    }

    if (selected.size >
        TelegramStorageService
            .maxStorageFileBytes) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error =
            'This file is ${_formatSize(selected.size)}. '
            'The current single-file storage limit '
            'is ${_formatSize(TelegramStorageService.maxStorageFileBytes)}. '
            'Automatic splitting will be added in '
            'the next storage step.';
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
  // FORGET LOCAL CONFIG
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
            'This only removes the local Fabularium '
            'configuration. The Telegram channel '
            'and its files will not be deleted.',
          ),
          actions: [
            TextButton(
              onPressed:
                  () {
                Navigator.of(context)
                    .pop(
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
                Navigator.of(context)
                    .pop(
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
        _buildHeader(),

        const SizedBox(
          height:
              24,
        ),

        if (_channel == null)
          _buildCreateStorageCard()
        else
          _buildStorageCard(
            _channel!,
          ),

        if (_isUploading) ...[
          const SizedBox(
            height:
                24,
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

        _buildCurrentPhaseCard(),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
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

        Text(
          'Use a private Telegram channel as '
          'secondary storage for your model files.',
          style:
              Theme.of(context)
                  .textTheme
                  .bodyLarge,
        ),
      ],
    );
  }

  // ============================================================
  // NOT CONFIGURED
  // ============================================================

  Widget _buildCreateStorageCard() {
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
                  Icons.cloud_outlined,
                  size:
                      32,
                ),
                SizedBox(
                  width:
                      12,
                ),
                Expanded(
                  child:
                      Text(
                    'Storage is not configured',
                    style:
                        TextStyle(
                      fontSize:
                          18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(
              height:
                  16,
            ),

            const Text(
              'Create a dedicated private channel '
              'or use one you already created.',
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
                          : _createChannel,
                  icon:
                      _isCreatingChannel
                          ? const SizedBox(
                              width:
                                  18,
                              height:
                                  18,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth:
                                    2,
                              ),
                            )
                          : const Icon(
                              Icons.add,
                            ),
                  label:
                      Text(
                    _isCreatingChannel
                        ? 'Creating...'
                        : 'Create New Storage Channel',
                  ),
                ),

                OutlinedButton.icon(
                  onPressed:
                      _isBusy
                          ? null
                          : _selectExistingChannel,
                  icon:
                      _isLoadingChannels
                          ? const SizedBox(
                              width:
                                  18,
                              height:
                                  18,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth:
                                    2,
                              ),
                            )
                          : const Icon(
                              Icons.cloud_queue,
                            ),
                  label:
                      Text(
                    _isLoadingChannels
                        ? 'Loading Channels...'
                        : 'Use Existing Telegram Channel',
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
  // CONFIGURED
  // ============================================================

  Widget _buildStorageCard(
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
                        style:
                            Theme.of(context)
                                .textTheme
                                .bodySmall,
                      ),
                    ],
                  ),
                ),

                const Chip(
                  avatar:
                      Icon(
                    Icons.check,
                    size:
                        16,
                  ),
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

            Text(
              'Single-file limit in this phase: '
              '${_formatSize(TelegramStorageService.maxStorageFileBytes)}',
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
                      _isLoadingChannels
                          ? const SizedBox(
                              width:
                                  18,
                              height:
                                  18,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth:
                                    2,
                              ),
                            )
                          : const Icon(
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

  // ============================================================
  // UPLOAD PROGRESS
  // ============================================================

  Widget _buildUploadProgress() {
    final percent =
        (_uploadProgress *
                100)
            .clamp(
              0,
              100,
            );

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
              maxLines:
                  2,
              overflow:
                  TextOverflow.ellipsis,
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
                  _uploadProgress,
            ),

            const SizedBox(
              height:
                  8,
            ),

            Text(
              '${percent.toStringAsFixed(0)}%',
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
                style:
                    TextStyle(
                  color:
                      Theme.of(context)
                          .colorScheme
                          .error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPhaseCard() {
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
              'Storage Phase 1',
              style:
                  Theme.of(context)
                      .textTheme
                      .titleMedium,
            ),

            const SizedBox(
              height:
                  12,
            ),

            const Text(
              '✓ Create private storage channel\n'
              '✓ Use existing private channel\n'
              '✓ Local channel configuration\n'
              '✓ Real MTProto file upload\n'
              '✓ Upload outside the UI isolate\n'
              '✓ Telegram message ID captured\n'
              '○ ZIP model folders\n'
              '○ Split archives above 1900 MB\n'
              '○ Manifest JSON\n'
              '○ Restore model from Storage',
            ),
          ],
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