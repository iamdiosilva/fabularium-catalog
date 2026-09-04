import 'package:flutter/material.dart';

import '../models/telegram_storage_channel.dart';
import '../models/telegram_storage_workspace.dart';
import '../services/telegram_storage_workspace_service.dart';

enum _ChannelRole {
  catalog,
  files,
  pending,
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
      _service =
      TelegramStorageWorkspaceService.instance;

  TelegramStorageWorkspace _workspace =
      const TelegramStorageWorkspace.empty();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final workspace =
          await _service.load();

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace = workspace;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _create(
    _ChannelRole role,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
      _status =
          'Creating ${_roleLabel(role)}...';
    });

    try {
      late final TelegramStorageWorkspace
          workspace;

      switch (role) {
        case _ChannelRole.catalog:
          workspace =
              await _service
                  .createCatalogChannel();
          break;
        case _ChannelRole.files:
          workspace =
              await _service
                  .createFilesChannel();
          break;
        case _ChannelRole.pending:
          workspace =
              await _service
                  .createPendingChannel();
          break;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace = workspace;
        _status =
            '${_roleLabel(role)} configured.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error =
              error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _select(
    _ChannelRole role,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
      _status =
          'Loading available channels...';
    });

    try {
      final channels =
          await _service
              .listAvailableChannels();

      if (!mounted) {
        return;
      }

      final usedIds =
          <int>{
        if (role !=
                _ChannelRole.catalog &&
            _workspace.catalogChannel !=
                null)
          _workspace.catalogChannel!.id,
        if (role !=
                _ChannelRole.files &&
            _workspace.filesChannel !=
                null)
          _workspace.filesChannel!.id,
        if (role !=
                _ChannelRole.pending &&
            _workspace.pendingChannel !=
                null)
          _workspace.pendingChannel!.id,
      };

      var selectable =
          channels
              .where(
                (channel) =>
                    !usedIds.contains(
                  channel.id,
                ),
              )
              .toList();

      if (role ==
          _ChannelRole.pending) {
        selectable =
            selectable
                .where(
                  (channel) =>
                      channel.isPrivate,
                )
                .toList();
      }

      final selected =
          await showDialog<
              TelegramStorageChannel>(
        context: context,
        builder: (context) =>
            AlertDialog(
          title: Text(
            'Select ${_roleLabel(role)}',
          ),
          content: SizedBox(
            width: 560,
            height: 440,
            child:
                selectable.isEmpty
                    ? Center(
                        child: Text(
                          role ==
                                  _ChannelRole
                                      .pending
                              ? 'No compatible private broadcast channels found.'
                              : 'No compatible broadcast channels found.',
                          textAlign:
                              TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount:
                            selectable.length,
                        itemBuilder:
                            (
                          context,
                          index,
                        ) {
                          final channel =
                              selectable[index];

                          return ListTile(
                            leading: Icon(
                              channel.isPublic
                                  ? Icons
                                      .public_outlined
                                  : Icons
                                      .lock_outline,
                            ),
                            title: Text(
                              channel.title,
                            ),
                            subtitle: Text(
                              _channelSubtitle(
                                channel,
                              ),
                            ),
                            onTap: () =>
                                Navigator.of(
                              context,
                            ).pop(
                              channel,
                            ),
                          );
                        },
                      ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(
                context,
              ).pop(),
              child: const Text(
                'Cancel',
              ),
            ),
          ],
        ),
      );

      if (selected == null) {
        return;
      }

      late final TelegramStorageWorkspace
          workspace;

      switch (role) {
        case _ChannelRole.catalog:
          workspace =
              await _service
                  .selectCatalogChannel(
            selected,
          );
          break;
        case _ChannelRole.files:
          workspace =
              await _service
                  .selectFilesChannel(
            selected,
          );
          break;
        case _ChannelRole.pending:
          workspace =
              await _service
                  .selectPendingChannel(
            selected,
          );
          break;
      }

      if (mounted) {
        setState(() {
          _workspace = workspace;
          _status =
              '${_roleLabel(role)} configured.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error =
              error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _clear(
    _ChannelRole role,
  ) async {
    setState(() {
      _busy = true;
    });

    try {
      late final TelegramStorageWorkspace
          workspace;

      switch (role) {
        case _ChannelRole.catalog:
          workspace =
              await _service
                  .clearCatalogChannel();
          break;
        case _ChannelRole.files:
          workspace =
              await _service
                  .clearFilesChannel();
          break;
        case _ChannelRole.pending:
          workspace =
              await _service
                  .clearPendingChannel();
          break;
      }

      if (mounted) {
        setState(() {
          _workspace = workspace;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error =
              error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Telegram Storage Settings',
        ),
      ),
      body:
          _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(),
                )
              : ListView(
                  padding:
                      const EdgeInsets.all(
                    24,
                  ),
                  children: [
                    Text(
                      'Community Storage Workspace',
                      style:
                          Theme.of(
                        context,
                      )
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight:
                                    FontWeight.bold,
                              ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    const Text(
                      'Catalog and Files are the approved official storage channels and may be public. '
                      'Pending is used only for community submissions waiting for moderation and must remain private.',
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    _workspaceStatus(),
                    const SizedBox(
                      height: 20,
                    ),
                    _channelCard(
                      _ChannelRole.catalog,
                      _workspace
                          .catalogChannel,
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    _channelCard(
                      _ChannelRole.files,
                      _workspace
                          .filesChannel,
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    _channelCard(
                      _ChannelRole.pending,
                      _workspace
                          .pendingChannel,
                    ),
                    if (_status !=
                        null) ...[
                      const SizedBox(
                        height: 16,
                      ),
                      Text(
                        _status!,
                      ),
                    ],
                    if (_error !=
                        null) ...[
                      const SizedBox(
                        height: 12,
                      ),
                      Text(
                        _error!,
                        style:
                            TextStyle(
                          color:
                              Theme.of(
                            context,
                          )
                                  .colorScheme
                                  .error,
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }

  Widget _workspaceStatus() {
    final ready =
        _workspace.isCommunityConfigured;

    return Card(
      child: ListTile(
        leading: Icon(
          ready
              ? Icons
                  .verified_outlined
              : Icons
                  .pending_actions_outlined,
        ),
        title: Text(
          ready
              ? 'Community Telegram workspace ready'
              : 'Community Telegram workspace incomplete',
        ),
        subtitle: Text(
          ready
              ? 'Catalog + Files + private Pending are configured.'
              : 'Configure all three channel roles before Community publishing.',
        ),
      ),
    );
  }

  Widget _channelCard(
    _ChannelRole role,
    TelegramStorageChannel? channel,
  ) {
    final icon =
        switch (role) {
      _ChannelRole.catalog =>
        Icons.photo_library_outlined,
      _ChannelRole.files =>
        Icons.archive_outlined,
      _ChannelRole.pending =>
        Icons.hourglass_top_outlined,
    };

    final description =
        switch (role) {
      _ChannelRole.catalog =>
        'Approved galleries and catalog media.',
      _ChannelRole.files =>
        'Approved package parts and manifests.',
      _ChannelRole.pending =>
        'Private staging for uploads awaiting admin review.',
    };

    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(
          18,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: Text(
                    _roleLabel(role),
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
                Chip(
                  avatar:
                      channel ==
                              null
                          ? null
                          : Icon(
                              channel
                                      .isPublic
                                  ? Icons
                                      .public_outlined
                                  : Icons
                                      .lock_outline,
                              size: 17,
                            ),
                  label: Text(
                    channel ==
                            null
                        ? 'Not configured'
                        : channel
                                .isPublic
                            ? 'PUBLIC'
                            : 'PRIVATE',
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              channel?.title ??
                  description,
            ),
            if (channel !=
                null) ...[
              const SizedBox(
                height: 6,
              ),
              SelectableText(
                'ID: ${channel.id}',
              ),
              if (channel
                      .publicUsername !=
                  null)
                SelectableText(
                  '@${channel.publicUsername}',
                ),
              if (role ==
                      _ChannelRole
                          .pending &&
                  channel.isPublic) ...[
                const SizedBox(
                  height: 8,
                ),
                Text(
                  'Pending cannot be public.',
                  style:
                      TextStyle(
                    color:
                        Theme.of(
                      context,
                    )
                            .colorScheme
                            .error,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ],
            const SizedBox(
              height: 14,
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  onPressed:
                      _busy
                          ? null
                          : () =>
                              _select(
                            role,
                          ),
                  icon:
                      const Icon(
                    Icons.list,
                  ),
                  label:
                      const Text(
                    'Select Existing',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _busy
                          ? null
                          : () =>
                              _create(
                            role,
                          ),
                  icon:
                      const Icon(
                    Icons.add,
                  ),
                  label: Text(
                    role ==
                            _ChannelRole
                                .pending
                        ? 'Create Private'
                        : 'Create',
                  ),
                ),
                if (channel !=
                    null)
                  TextButton.icon(
                    onPressed:
                        _busy
                            ? null
                            : () =>
                                _clear(
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
        ),
      ),
    );
  }

  String _roleLabel(
    _ChannelRole role,
  ) {
    return switch (role) {
      _ChannelRole.catalog =>
        'Catalog Channel',
      _ChannelRole.files =>
        'Files Channel',
      _ChannelRole.pending =>
        'Pending Channel',
    };
  }

  String _channelSubtitle(
    TelegramStorageChannel channel,
  ) {
    final visibility =
        channel.isPublic
            ? 'PUBLIC'
            : 'PRIVATE';

    final username =
        channel.publicUsername;

    if (username == null) {
      return '$visibility · ID ${channel.id}';
    }

    return '$visibility · @$username · ID ${channel.id}';
  }
}
