class TelegramGroup {
  final int id;
  final String title;
  final int? accessHash;

  final bool isChannel;

  const TelegramGroup({
    required this.id,
    required this.title,
    required this.accessHash,
    required this.isChannel,
  });

  @override
  String toString() {
    return 'TelegramGroup('
        'id: $id, '
        'title: $title, '
        'accessHash: $accessHash, '
        'isChannel: $isChannel'
        ')';
  }
}