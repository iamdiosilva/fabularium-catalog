import 'package:flutter/material.dart';

import '../models/telegram_storage_channel.dart';
import '../models/telegram_storage_workspace.dart';
import '../services/telegram_storage_workspace_service.dart';

enum _TelegramStorageChannelRole {
  catalog,
  files,
}

class TelegramStorageSettingsPage
    extends StatefulWidget {
  const TelegramStorageSettingsPage({
    super.key,
  });

  @override
  State<TelegramStorageSettingsPage>
      createState() =>
          _TelegramStorageSettingsPageState();
}

class _TelegramStorageSettingsPageState
    extends State<TelegramStorageSettingsPage> {
  final TelegramStorageWorkspaceService
      _workspaceService =
      TelegramStorageWorkspaceService.instance;

  TelegramStorageWorkspace _workspace =
      const TelegramStorageWorkspace.empty();

  bool _isLoading =
      true;

  bool _isCreatingChannel =
      false;

  bool _isLoadingChannels =
      false;

  String? _error;

  String? _status;

  bool get _isBusy =>
      _isCreatingChannel ||
      _isLoadingChannels;

  int get _configuredChannelCount =>
      (_workspace.hasCatalogChannel
              ? 1
              : 0) +
          (_workspace.hasFilesChannel
              ? 1
              : 0);

  @override
  void initState() {
    super.initState();

    _loadStorage();
  }

  Future<void> _loadStorage() async {
    try {
      final workspace =
          await _workspaceService.load();

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace =
            workspace;
        _isLoading =
            false;
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

  String _channelRoleTitle(
    _TelegramStorageChannelRole role,
  ) {
    return role ==
            _TelegramStorageChannelRole.catalog
        ? 'Catalog Channel'
        : 'Files Channel';
  }

  String _channelRoleDescription(
    _TelegramStorageChannelRole role,
  ) {
    return role ==
            _TelegramStorageChannelRole.catalog
        ? 'Stores galleries, preview images and model metadata.'
        : 'Stores ZIP files, split parts and package manifests.';
  }

  TelegramStorageChannel?
      _channelForRole(
    _TelegramStorageChannelRole role,
  ) {
    return role ==
            _TelegramStorageChannelRole.catalog
        ? _workspace.catalogChannel
        : _workspace.filesChannel;
  }

  TelegramStorageChannel?
      _otherChannelForRole(
    _TelegramStorageChannelRole role,
  ) {
    return role ==
            _TelegramStorageChannelRole.catalog
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
        _channelRoleTitle(
      role,
    );

    setState(() {
      _isCreatingChannel =
          true;
      _error =
          null;
      _status =
          'Creating $roleTitle...';
    });

    try {
      final workspace =
          role ==
                  _TelegramStorageChannelRole.catalog
              ? await _workspaceService
                  .createCatalogChannel()
              : await _workspaceService
                  .createFilesChannel();

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace =
            workspace;
        _isCreatingChannel =
            false;
        _error =
            null;
        _status =
            '$roleTitle created and configured successfully.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isCreatingChannel =
            false;
        _status =
            null;
        _error =
            e.toString();
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
        _channelRoleTitle(
      role,
    );

    final otherChannel =
        _otherChannelForRole(
      role,
    );

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
          await _workspaceService
              .listAvailableChannels();

      if (!mounted) {
        return;
      }

      final selectableChannels =
          channels
              .where(
                (
                  channel,
                ) =>
                    channel.id !=
                    otherChannel?.id,
              )
              .toList();

      setState(() {
        _isLoadingChannels =
            false;
        _status =
            null;
      });

      if (selectableChannels
          .isEmpty) {
        setState(() {
          _error =
              otherChannel ==
                      null
                  ? 'No writable private Telegram channels were found.'
                  : 'No other writable private Telegram channel is available. '
                      'Catalog Channel and Files Channel must be different.';
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
                Text(
              'Select $roleTitle',
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
                    _channelRoleDescription(
                      role,
                    ),
                  ),
                  const SizedBox(
                    height:
                        16,
                  ),
                  Expanded(
                    child:
                        ListView.separated(
                      itemCount:
                          selectableChannels.length,
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
                            selectableChannels[
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

      if (selected ==
              null ||
          !mounted) {
        return;
      }

      final workspace =
          role ==
                  _TelegramStorageChannelRole.catalog
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
        _workspace =
            workspace;
        _error =
            null;
        _status =
            'Using "${selected.title}" as $roleTitle.';
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

  Future<void> _forgetWorkspaceChannel(
    _TelegramStorageChannelRole role,
  ) async {
    if (_isBusy) {
      return;
    }

    final channel =
        _channelForRole(
      role,
    );

    if (channel ==
        null) {
      return;
    }

    final roleTitle =
        _channelRoleTitle(
      role,
    );

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
              Text(
            'Forget $roleTitle?',
          ),
          content:
              Text(
            'This removes only the local $roleTitle configuration. '
            'Nothing will be deleted from Telegram.',
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

    if (confirmed !=
            true ||
        !mounted) {
      return;
    }

    try {
      final workspace =
          role ==
                  _TelegramStorageChannelRole.catalog
              ? await _workspaceService
                  .clearCatalogChannel()
              : await _workspaceService
                  .clearFilesChannel();

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace =
            workspace;
        _error =
            null;
        _status =
            '$roleTitle configuration removed.';
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

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar:
          AppBar(
        title:
            const Text(
          'Storage Settings',
        ),
        actions: [
          IconButton(
            tooltip:
                'Refresh',
            onPressed:
                _isBusy
                    ? null
                    : _loadStorage,
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
          'Storage Workspace',
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
              8,
        ),
        const Text(
          'Catalog and file storage use different private Telegram channels.',
        ),
        const SizedBox(
          height:
              24,
        ),
        _buildWorkspaceCard(),
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
      ],
    );
  }

  Widget _buildWorkspaceCard() {
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
                  Icons.account_tree_outlined,
                  size:
                      30,
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
                      const Text(
                        'Telegram Storage V3',
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
                            4,
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
                  label:
                      Text(
                    _workspace.isFullyConfigured
                        ? 'Ready'
                        : '$_configuredChannelCount / 2',
                  ),
                ),
              ],
            ),
            const SizedBox(
              height:
                  20,
            ),
            _buildChannelSection(
              role:
                  _TelegramStorageChannelRole.catalog,
              icon:
                  Icons.photo_library_outlined,
            ),
            const Divider(
              height:
                  36,
            ),
            _buildChannelSection(
              role:
                  _TelegramStorageChannelRole.files,
              icon:
                  Icons.inventory_2_outlined,
            ),
            const SizedBox(
              height:
                  16,
            ),
            Text(
              'The legacy single storage channel is migrated to '
              'Files Channel automatically.',
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
        _channelForRole(
      role,
    );

    final title =
        _channelRoleTitle(
      role,
    );

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
              size:
                  28,
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
                    title.toUpperCase(),
                    style:
                        const TextStyle(
                      fontSize:
                          15,
                      fontWeight:
                          FontWeight.bold,
                      letterSpacing:
                          0.6,
                    ),
                  ),
                  const SizedBox(
                    height:
                        4,
                  ),
                  Text(
                    _channelRoleDescription(
                      role,
                    ),
                  ),
                  if (channel !=
                      null) ...[
                    const SizedBox(
                      height:
                          10,
                    ),
                    Row(
                      children: [
                        const Icon(
                          Icons.cloud_done_outlined,
                          size:
                              18,
                        ),
                        const SizedBox(
                          width:
                              8,
                        ),
                        Expanded(
                          child:
                              Text(
                            '${channel.title} • ID ${channel.id}',
                            maxLines:
                                1,
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
                          width:
                              8,
                        ),
                        const Chip(
                          label:
                              Text(
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
          height:
              14,
        ),
        Wrap(
          spacing:
              12,
          runSpacing:
              12,
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
                Icons.cloud_queue,
              ),
              label:
                  const Text(
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
              icon:
                  const Icon(
                Icons.add,
              ),
              label:
                  const Text(
                'Create',
              ),
            ),
            if (channel !=
                null)
              TextButton.icon(
                onPressed:
                    _isBusy
                        ? null
                        : () =>
                            _forgetWorkspaceChannel(
                              role,
                            ),
                icon:
                    const Icon(
                  Icons.link_off,
                ),
                label:
                    const Text(
                  'Forget',
                ),
              ),
          ],
        ),
      ],
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
              Icons.info_outline,
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
}
