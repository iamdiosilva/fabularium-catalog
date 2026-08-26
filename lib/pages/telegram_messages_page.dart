import 'package:flutter/material.dart';

import '../models/telegram_group.dart';
import '../models/telegram_message.dart';
import '../services/download_queue_service.dart';
import '../services/telegram_client.dart';
import '../services/telegram_preview_manager.dart';
import '../services/telegram_service.dart';

class TelegramMessagesPage extends StatefulWidget {
  final TelegramGroup group;
  const TelegramMessagesPage({super.key, required this.group});

  @override
  State<TelegramMessagesPage> createState() => _TelegramMessagesPageState();
}

class _TelegramMessagesPageState extends State<TelegramMessagesPage> {
  final TelegramService _telegram = TelegramService.instance;
  List<TelegramMessage> _messages = const [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    TelegramClient.instance.disconnect();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      await TelegramClient.instance.connect();
      final offset = reset || _messages.isEmpty ? 0 : _messages.last.id;
      final page = await _telegram.getMessages(widget.group, limit: 50, offsetId: offset);
      if (!mounted) return;
      setState(() {
        _messages = reset ? page : <TelegramMessage>[..._messages, ...page];
        _hasMore = page.length >= 50;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _loadingMore = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.group.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: FilledButton.tonal(
                            onPressed: _loadingMore ? null : () => _load(reset: false),
                            child: _loadingMore
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Load Older Messages'),
                          ),
                        ),
                      );
                    }
                    return _MessageCard(message: _messages[index], groupTitle: widget.group.title);
                  },
                ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final TelegramMessage message;
  final String groupTitle;
  const _MessageCard({required this.message, required this.groupTitle});

  @override
  Widget build(BuildContext context) {
    final media = message.media;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.sender, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (message.text.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              SelectableText(message.text),
            ],
            if (media != null) ...[
              const SizedBox(height: 10),
              if (media.hasPreview || media.isPhoto)
                FutureBuilder(
                  future: TelegramPreviewManager.instance.getPreview(media),
                  builder: (context, snapshot) {
                    final file = snapshot.data;
                    if (file == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: Image.file(file, fit: BoxFit.contain),
                      ),
                    );
                  },
                ),
              Row(
                children: [
                  Expanded(child: Text(media.fileName, overflow: TextOverflow.ellipsis)),
                  FilledButton.tonalIcon(
                    onPressed: () => DownloadQueueService.instance.enqueue(media: media, groupTitle: groupTitle),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Download'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
