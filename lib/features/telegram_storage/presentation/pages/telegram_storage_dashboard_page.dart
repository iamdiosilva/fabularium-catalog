import 'package:flutter/material.dart';

import '../../../../services/telegram_storage_upload_journal_service.dart';
import '../../../../services/telegram_storage_workspace_service.dart';
import '../../../../models/telegram_storage_workspace.dart';
import '../../../../pages/telegram_storage_settings_page.dart';
import '../../../../pages/telegram_storage_upload_page.dart';
import 'telegram_storage_recovery_page.dart';

class TelegramStoragePage extends StatefulWidget {
  const TelegramStoragePage({super.key});

  @override
  State<TelegramStoragePage> createState() => _TelegramStoragePageState();
}

class _TelegramStoragePageState extends State<TelegramStoragePage> {
  final TelegramStorageWorkspaceService _workspaceService =
      TelegramStorageWorkspaceService.instance;
  final TelegramStorageUploadJournalService _journalService =
      TelegramStorageUploadJournalService.instance;

  TelegramStorageWorkspace _workspace = const TelegramStorageWorkspace.empty();
  int _incomplete = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final workspace = await _workspaceService.load();
      final journals = await _journalService.listIncomplete();
      if (!mounted) return;
      setState(() {
        _workspace = workspace;
        _incomplete = journals.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Telegram Storage'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Storage V3',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Catalog metadata and galleries are separated from package files, '
                  'with persistent journals for verification and recovery.',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_error!)),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _DashboardTile(
                  icon: Icons.settings_outlined,
                  title: 'Storage Settings',
                  subtitle: _workspace.isFullyConfigured
                      ? 'Catalog: ${_workspace.catalogChannel!.title} · '
                          'Files: ${_workspace.filesChannel!.title}'
                      : 'Configure Catalog Channel and Files Channel.',
                  trailing: _workspace.isFullyConfigured
                      ? const Icon(Icons.check_circle_outline)
                      : const Icon(Icons.warning_amber_rounded),
                  onTap: () => _open(const TelegramStorageSettingsPage()),
                ),
                const SizedBox(height: 12),
                _DashboardTile(
                  icon: Icons.cloud_upload_outlined,
                  title: 'Upload Models',
                  subtitle: 'Prepare and upload Storage V3 packages.',
                  onTap: () => _open(const TelegramStorageUploadPage()),
                ),
                const SizedBox(height: 12),
                _DashboardTile(
                  icon: Icons.health_and_safety_outlined,
                  title: 'Upload Recovery',
                  subtitle: _incomplete == 0
                      ? 'No incomplete uploads.'
                      : '$_incomplete package${_incomplete == 1 ? '' : 's'} '
                          'waiting for Repair, Resume or Clean.',
                  trailing: Chip(label: Text('$_incomplete')),
                  onTap: () => _open(const TelegramStorageRecoveryPage()),
                ),
              ],
            ),
    );
  }
}

class _DashboardTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _DashboardTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: Icon(icon, size: 30),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: trailing ?? const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
