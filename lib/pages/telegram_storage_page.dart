import 'package:flutter/material.dart';

import '../models/telegram_storage_workspace.dart';
import '../services/telegram_storage_upload_journal_service.dart';
import '../services/telegram_storage_workspace_service.dart';
import 'telegram_storage_recovery_page.dart';
import 'telegram_storage_settings_page.dart';

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
  final TelegramStorageWorkspaceService
      _workspaceService =
      TelegramStorageWorkspaceService.instance;

  final TelegramStorageUploadJournalService
      _journalService =
      TelegramStorageUploadJournalService.instance;

  TelegramStorageWorkspace _workspace =
      const TelegramStorageWorkspace.empty();

  int _incompleteUploads =
      0;

  bool _isLoading =
      true;

  String? _error;

  @override
  void initState() {
    super.initState();

    _refreshSummary();
  }

  Future<void> _refreshSummary() async {
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
      final workspace =
          await _workspaceService.load();

      final journals =
          await _journalService.listIncomplete();

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace =
            workspace;
        _incompleteUploads =
            journals.length;
        _isLoading =
            false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error =
            e.toString();
        _isLoading =
            false;
      });
    }
  }

  Future<void> _openRecovery() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) =>
                const TelegramStorageRecoveryPage(),
      ),
    );

    await _refreshSummary();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) =>
                const TelegramStorageSettingsPage(),
      ),
    );

    await _refreshSummary();
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
          'Telegram Storage',
        ),
        actions: [
          IconButton(
            tooltip:
                'Refresh',
            onPressed:
                _isLoading
                    ? null
                    : _refreshSummary,
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
          'Fabularium Storage',
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
          'Model uploads now start directly from the Fabularium Catalog '
          'model details page. This area is used only for Storage V3 '
          'administration and recovery.',
        ),
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
              24,
        ),
        Card(
          child:
              Padding(
            padding:
                const EdgeInsets.all(
              20,
            ),
            child:
                Row(
              children: [
                const CircleAvatar(
                  radius:
                      28,
                  child:
                      Icon(
                    Icons.collections_bookmark_outlined,
                    size:
                        28,
                  ),
                ),
                const SizedBox(
                  width:
                      18,
                ),
                Expanded(
                  child:
                      Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Model Uploads',
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
                      const Text(
                        'Open a model in Fabularium Catalog and use its '
                        'Telegram Storage card to upload it.',
                      ),
                    ],
                  ),
                ),
                Chip(
                  label:
                      Text(
                    _workspace.isFullyConfigured
                        ? 'Ready'
                        : 'Setup required',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(
          height:
              16,
        ),
        _buildNavigationCard(
          icon:
              Icons.restore_outlined,
          title:
              'Upload Recovery',
          description:
              'Resume interrupted uploads and clean incomplete '
              'Telegram Storage packages.',
          status:
              _incompleteUploads ==
                      0
                  ? 'Clear'
                  : '$_incompleteUploads incomplete',
          onTap:
              _openRecovery,
        ),
        const SizedBox(
          height:
              16,
        ),
        _buildNavigationCard(
          icon:
              Icons.settings_outlined,
          title:
              'Storage Settings',
          description:
              'Configure the Catalog Channel and Files Channel '
              'used by Storage V3.',
          status:
              _workspace.isFullyConfigured
                  ? '2 / 2 configured'
                  : '${_configuredChannelCount()} / 2 configured',
          onTap:
              _openSettings,
        ),
        const SizedBox(
          height:
              24,
        ),
        Card(
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
                  'Storage V3 Architecture',
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
                      12,
                ),
                Text(
                  'Catalog Channel: '
                  '${_workspace.catalogChannel?.title ?? 'Not configured'}',
                ),
                Text(
                  'Files Channel: '
                  '${_workspace.filesChannel?.title ?? 'Not configured'}',
                ),
                const SizedBox(
                  height:
                      12,
                ),
                const Text(
                  'Catalog Channel stores galleries and metadata. '
                  'Files Channel stores ZIPs, split parts and manifests.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  int _configuredChannelCount() {
    int result =
        0;

    if (_workspace
        .hasCatalogChannel) {
      result++;
    }

    if (_workspace
        .hasFilesChannel) {
      result++;
    }

    return result;
  }

  Widget _buildNavigationCard({
    required IconData icon,
    required String title,
    required String description,
    required String status,
    required VoidCallback onTap,
  }) {
    return Card(
      clipBehavior:
          Clip.antiAlias,
      child:
          InkWell(
        onTap:
            onTap,
        child:
            Padding(
          padding:
              const EdgeInsets.all(
            20,
          ),
          child:
              Row(
            children: [
              CircleAvatar(
                radius:
                    28,
                child:
                    Icon(
                  icon,
                  size:
                      28,
                ),
              ),
              const SizedBox(
                width:
                    18,
              ),
              Expanded(
                child:
                    Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style:
                          const TextStyle(
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
                      description,
                    ),
                  ],
                ),
              ),
              const SizedBox(
                width:
                    16,
              ),
              Chip(
                label:
                    Text(
                  status,
                ),
              ),
              const SizedBox(
                width:
                    8,
              ),
              const Icon(
                Icons.chevron_right,
              ),
            ],
          ),
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
