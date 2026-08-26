import 'package:flutter/material.dart';

import '../models/telegram_storage_channel.dart';
import '../models/telegram_storage_workspace.dart';
import '../services/telegram_storage_workspace_service.dart';

enum _ChannelRole { catalog, files }

class TelegramStorageSettingsPage extends StatefulWidget {
  const TelegramStorageSettingsPage({super.key});
  @override
  State<TelegramStorageSettingsPage> createState() => _TelegramStorageSettingsPageState();
}

class _TelegramStorageSettingsPageState extends State<TelegramStorageSettingsPage> {
  final TelegramStorageWorkspaceService _service = TelegramStorageWorkspaceService.instance;
  TelegramStorageWorkspace _workspace = const TelegramStorageWorkspace.empty();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _status;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final workspace = await _service.load();
      if (!mounted) return;
      setState(() { _workspace = workspace; _loading = false; _error = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _create(_ChannelRole role) async {
    setState(() { _busy = true; _error = null; _status = 'Creating channel...'; });
    try {
      final workspace = role == _ChannelRole.catalog
          ? await _service.createCatalogChannel()
          : await _service.createFilesChannel();
      if (!mounted) return;
      setState(() { _workspace = workspace; _status = 'Channel configured.'; });
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _select(_ChannelRole role) async {
    setState(() { _busy = true; _error = null; _status = 'Loading private channels...'; });
    try {
      final channels = await _service.listAvailableChannels();
      if (!mounted) return;
      final otherId = role == _ChannelRole.catalog ? _workspace.filesChannel?.id : _workspace.catalogChannel?.id;
      final selectable = channels.where((c) => c.id != otherId).toList();
      final selected = await showDialog<TelegramStorageChannel>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(role == _ChannelRole.catalog ? 'Select Catalog Channel' : 'Select Files Channel'),
          content: SizedBox(
            width: 520,
            height: 420,
            child: selectable.isEmpty
                ? const Center(child: Text('No compatible private channels found.'))
                : ListView.builder(
                    itemCount: selectable.length,
                    itemBuilder: (_, i) => ListTile(
                      leading: const Icon(Icons.campaign_outlined),
                      title: Text(selectable[i].title),
                      subtitle: Text('ID ${selectable[i].id}'),
                      onTap: () => Navigator.of(context).pop(selectable[i]),
                    ),
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
        ),
      );
      if (selected != null) {
        final workspace = role == _ChannelRole.catalog
            ? await _service.selectCatalogChannel(selected)
            : await _service.selectFilesChannel(selected);
        if (mounted) setState(() { _workspace = workspace; _status = 'Channel configured.'; });
      }
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _clear(_ChannelRole role) async {
    setState(() => _busy = true);
    try {
      final workspace = role == _ChannelRole.catalog
          ? await _service.clearCatalogChannel()
          : await _service.clearFilesChannel();
      if (mounted) setState(() => _workspace = workspace);
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Telegram Storage Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Storage V3 Workspace', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Catalog stores galleries and metadata. Files stores ZIP parts and manifests. The channels must be different.'),
                const SizedBox(height: 20),
                _channelCard(_ChannelRole.catalog, _workspace.catalogChannel),
                const SizedBox(height: 16),
                _channelCard(_ChannelRole.files, _workspace.filesChannel),
                if (_status != null) ...[const SizedBox(height: 16), Text(_status!)],
                if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
              ],
            ),
    );
  }

  Widget _channelCard(_ChannelRole role, TelegramStorageChannel? channel) {
    final isCatalog = role == _ChannelRole.catalog;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(isCatalog ? Icons.photo_library_outlined : Icons.archive_outlined),
            const SizedBox(width: 10),
            Expanded(child: Text(isCatalog ? 'Catalog Channel' : 'Files Channel', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
            Chip(label: Text(channel == null ? 'Not configured' : 'Configured')),
          ]),
          const SizedBox(height: 8),
          Text(channel?.title ?? (isCatalog ? 'Stores gallery images and model metadata.' : 'Stores package parts and final manifests.')),
          if (channel != null) ...[const SizedBox(height: 6), SelectableText('ID: ${channel.id}')],
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.tonalIcon(onPressed: _busy ? null : () => _select(role), icon: const Icon(Icons.list), label: const Text('Select Existing')),
            OutlinedButton.icon(onPressed: _busy ? null : () => _create(role), icon: const Icon(Icons.add), label: const Text('Create')),
            if (channel != null) TextButton.icon(onPressed: _busy ? null : () => _clear(role), icon: const Icon(Icons.link_off), label: const Text('Forget')),
          ]),
        ]),
      ),
    );
  }
}
