class CommunityProfile {
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final int points;
  final int reputation;
  final int approvedUploads;
  final int likesReceived;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CommunityProfile({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.bio,
    required this.points,
    required this.reputation,
    required this.approvedUploads,
    required this.likesReceived,
    required this.createdAt,
    required this.updatedAt,
  });

  String get level {
    if (points >= 5000) {
      return 'Master Archivist';
    }

    if (points >= 1500) {
      return 'Curator';
    }

    if (points >= 500) {
      return 'Trusted Contributor';
    }

    if (points >= 100) {
      return 'Contributor';
    }

    return 'Novice';
  }

  factory CommunityProfile.fromJson(
    Map<String, dynamic> json,
  ) {
    return CommunityProfile(
      userId:
          json['user_id']?.toString() ?? '',
      username:
          json['username']?.toString() ?? '',
      displayName:
          json['display_name']?.toString() ?? '',
      avatarUrl:
          _nullableString(json['avatar_url']),
      bio:
          _nullableString(json['bio']),
      points:
          _readInt(json['points']),
      reputation:
          _readInt(json['reputation']),
      approvedUploads:
          _readInt(json['approved_uploads']),
      likesReceived:
          _readInt(json['likes_received']),
      createdAt:
          _readDate(json['created_at']),
      updatedAt:
          _readDate(json['updated_at']),
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

DateTime _readDate(dynamic value) {
  return DateTime.tryParse(
        value?.toString() ?? '',
      ) ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

String? _nullableString(dynamic value) {
  final text =
      value?.toString().trim() ?? '';

  return text.isEmpty
      ? null
      : text;
}
