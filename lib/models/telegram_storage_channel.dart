class TelegramStorageChannel {
  final int id;

  final int accessHash;

  final String title;

  const TelegramStorageChannel({
    required this.id,
    required this.accessHash,
    required this.title,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'accessHash': accessHash,
      'title': title,
    };
  }

  factory TelegramStorageChannel.fromJson(
    Map<String, dynamic> json,
  ) {
    return TelegramStorageChannel(
      id: json['id'] as int,
      accessHash:
          json['accessHash'] as int,
      title:
          json['title'] as String,
    );
  }
}