import 'package:flutter/material.dart';

import '../models/telegram_group.dart';
import '../models/telegram_message.dart';
import '../services/telegram_service.dart';

class TelegramMessagesPage
    extends StatefulWidget {
  final TelegramGroup group;

  const TelegramMessagesPage({
    super.key,
    required this.group,
  });

  @override
  State<TelegramMessagesPage>
      createState() =>
          _TelegramMessagesPageState();
}

class _TelegramMessagesPageState
    extends State<TelegramMessagesPage> {
  final TelegramService _telegram =
      TelegramService.instance;

  bool _isLoading = true;

  String? _error;

  List<TelegramMessage> _messages =
      [];

  @override
  void initState() {
    super.initState();

    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final messages =
          await _telegram.getMessages(
        widget.group,
        limit: 50,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _messages =
            messages;

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

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.group.title,
        ),
        actions: [
          IconButton(
            tooltip:
                'Refresh Messages',
            onPressed:
                _isLoading
                    ? null
                    : _loadMessages,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding:
              const EdgeInsets.all(
            24,
          ),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
              ),

              const SizedBox(
                height: 16,
              ),

              const Text(
                'Error loading messages',
              ),

              const SizedBox(
                height: 12,
              ),

              Text(
                _error!,
                textAlign:
                    TextAlign.center,
              ),

              const SizedBox(
                height: 20,
              ),

              FilledButton.icon(
                onPressed:
                    _loadMessages,
                icon: const Icon(
                  Icons.refresh,
                ),
                label: const Text(
                  'Try Again',
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Icon(
              Icons
                  .chat_bubble_outline,
              size: 72,
            ),
            SizedBox(
              height: 16,
            ),
            Text(
              'No messages found.',
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      reverse: false,
      padding:
          const EdgeInsets.all(
        20,
      ),
      itemCount:
          _messages.length,
      separatorBuilder:
          (
        context,
        index,
      ) =>
              const SizedBox(
        height: 12,
      ),
      itemBuilder:
          (
        context,
        index,
      ) {
        final message =
            _messages[index];

        return _MessageCard(
          message:
              message,
        );
      },
    );
  }
}

class _MessageCard
    extends StatelessWidget {
  final TelegramMessage message;

  const _MessageCard({
    required this.message,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(
          16,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment
                  .start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons
                      .person_outline,
                  size: 18,
                ),

                const SizedBox(
                  width: 8,
                ),

                Expanded(
                  child: Text(
                    message.sender,
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),

                if (message.date != null)
                  Text(
                    _formatDate(
                      message.date!,
                    ),
                    style:
                        Theme.of(context)
                            .textTheme
                            .bodySmall,
                  ),
              ],
            ),

            const SizedBox(
              height: 10,
            ),

            SelectableText(
              message.text,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(
    DateTime date,
  ) {
    final local =
        date.toLocal();

    String twoDigits(
      int value,
    ) {
      return value
          .toString()
          .padLeft(
            2,
            '0',
          );
    }

    return '${twoDigits(local.day)}/'
        '${twoDigits(local.month)}/'
        '${local.year} '
        '${twoDigits(local.hour)}:'
        '${twoDigits(local.minute)}';
  }
}