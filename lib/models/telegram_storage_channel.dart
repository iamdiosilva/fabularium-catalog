class TelegramStorageChannel {
  final int id;
  final int accessHash;
  final String title;
  final String? username;

  const TelegramStorageChannel({
    required this.id,
    required this.accessHash,
    required this.title,
    this.username,
  });

  bool get isPublic =>
      username != null &&
      username!.trim().isNotEmpty;

  bool get isPrivate =>
      !isPublic;

  String? get publicUsername {
    final value = username?.trim() ?? '';

    return value.isEmpty
        ? null
        : value;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'accessHash': accessHash,
      'title': title,
      'username': publicUsername,
    };
  }

  factory TelegramStorageChannel.fromJson(
    Map<String, dynamic> json,
  ) {
    return TelegramStorageChannel(
      id: _readInt(json['id']),
      accessHash: _readInt(
        json['accessHash'],
      ),
      title:
          json['title']?.toString() ?? '',
      username:
          _readNullableString(
        json['username'],
      ),
    );
  }
}

int _readInt(dynamic value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(
        value?.toString() ?? '',
      ) ??
      0;
}

String? _readNullableString(
  dynamic value,
) {
  final text =
      value?.toString().trim() ?? '';

  return text.isEmpty
      ? null
      : text;
}
