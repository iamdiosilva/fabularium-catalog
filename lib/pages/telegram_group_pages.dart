import 'package:flutter/material.dart';
import 'package:t/t.dart' as t;

import '../models/telegram_group.dart';
import '../services/telegram_client.dart';
import 'telegram_messages_page.dart';

class TelegramGroupPages extends StatefulWidget {
  const TelegramGroupPages({super.key});

  @override
  State<TelegramGroupPages> createState() => _TelegramGroupPagesState();
}

class _TelegramGroupPagesState extends State<TelegramGroupPages> {
  List<TelegramGroup> _groups = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final telegram = TelegramClient.instance;
      final client = await telegram.connect();
      final response = await client.messages.getDialogs(
        excludePinned: false,
        offsetDate: DateTime.fromMillisecondsSinceEpoch(0),
        offsetId: 0,
        offsetPeer: const t.InputPeerEmpty(),
        limit: 100,
        hash: 0,
      );
      if (response.error != null) throw Exception(response.error!.errorMessage);
      final result = response.result;
      final items = <TelegramGroup>[];
      if (result != null) {
        List<dynamic> chats = const [];
        try { chats = List<dynamic>.from((result as dynamic).chats as List); } catch (_) {}
        for (final chat in chats) {
          if (chat is t.Channel) {
            final hash = chat.accessHash;
            if (hash == null) continue;
            items.add(TelegramGroup(
              id: chat.id,
              title: chat.title,
              accessHash: hash,
              isChannel: true,
            ));
          } else if (chat is t.Chat) {
            items.add(TelegramGroup(
              id: chat.id,
              title: chat.title,
              accessHash: null,
              isChannel: false,
            ));
          }
        }
      }
      items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      await telegram.disconnect();
      if (!mounted) return;
      setState(() { _groups = items; _loading = false; });
    } catch (e) {
      try { await TelegramClient.instance.disconnect(); } catch (_) {}
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Telegram Groups'),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.separated(
                  itemCount: _groups.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final group = _groups[index];
                    return ListTile(
                      leading: Icon(group.isChannel ? Icons.campaign_outlined : Icons.groups_outlined),
                      title: Text(group.title),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => TelegramMessagesPage(group: group)),
                      ),
                    );
                  },
                ),
    );
  }
}

// Compatibility alias used by older navigation code.
class TelegramGroupsPage extends TelegramGroupPages {
  const TelegramGroupsPage({super.key});
}
