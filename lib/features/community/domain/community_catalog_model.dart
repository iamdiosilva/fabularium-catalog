class CommunityCatalogModel {
  final String modelId;
  final String packageId;
  final String name;
  final String? studio;
  final String? category;
  final String? type;
  final String? scale;
  final String? height;
  final String? description;
  final List<String> tags;

  final String? contributorId;
  final String? contributorUsername;
  final String? contributorDisplayName;
  final String? contributorAvatarUrl;

  final int likeCount;
  final int archiveSize;
  final int partCount;
  final DateTime? publishedAt;

  const CommunityCatalogModel({
    required this.modelId,
    required this.packageId,
    required this.name,
    required this.studio,
    required this.category,
    required this.type,
    required this.scale,
    required this.height,
    required this.description,
    required this.tags,
    required this.contributorId,
    required this.contributorUsername,
    required this.contributorDisplayName,
    required this.contributorAvatarUrl,
    required this.likeCount,
    required this.archiveSize,
    required this.partCount,
    required this.publishedAt,
  });

  String get contributorLabel {
    final displayName = contributorDisplayName?.trim() ?? '';
    if (displayName.isNotEmpty) return displayName;

    final username = contributorUsername?.trim() ?? '';
    if (username.isNotEmpty) return '@$username';

    return 'Fabularium contributor';
  }

  factory CommunityCatalogModel.fromJson(Map<String, dynamic> json) {
    final tags = <String>[];
    final rawTags = json['tags'];
    if (rawTags is List) {
      for (final raw in rawTags) {
        final value = raw?.toString().trim() ?? '';
        if (value.isNotEmpty) tags.add(value);
      }
    }

    return CommunityCatalogModel(
      modelId: json['modelId']?.toString() ?? '',
      packageId: json['packageId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled Model',
      studio: _nullable(json['studio']),
      category: _nullable(json['category']),
      type: _nullable(json['type']),
      scale: _nullable(json['scale']),
      height: _nullable(json['height']),
      description: _nullable(json['description']),
      tags: tags,
      contributorId: _nullable(json['contributorId']),
      contributorUsername: _nullable(json['contributorUsername']),
      contributorDisplayName: _nullable(json['contributorDisplayName']),
      contributorAvatarUrl: _nullable(json['contributorAvatarUrl']),
      likeCount: _readInt(json['likeCount']),
      archiveSize: _readInt(json['archiveSize']),
      partCount: _readInt(json['partCount']),
      publishedAt: _readDate(json['publishedAt']),
    );
  }
}

class CommunityCatalogPageResult {
  final List<CommunityCatalogModel> items;
  final int total;

  const CommunityCatalogPageResult({
    required this.items,
    required this.total,
  });

  factory CommunityCatalogPageResult.fromJson(Map<String, dynamic> json) {
    final items = <CommunityCatalogModel>[];
    final rawItems = json['items'];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is Map) {
          items.add(
            CommunityCatalogModel.fromJson(
              Map<String, dynamic>.from(raw),
            ),
          );
        }
      }
    }

    return CommunityCatalogPageResult(
      items: items,
      total: _readInt(json['total']),
    );
  }
}

class CommunityCatalogFilters {
  final List<String> categories;
  final List<String> studios;

  const CommunityCatalogFilters({
    required this.categories,
    required this.studios,
  });

  const CommunityCatalogFilters.empty()
      : categories = const <String>[],
        studios = const <String>[];

  factory CommunityCatalogFilters.fromJson(Map<String, dynamic> json) {
    List<String> readList(dynamic raw) {
      if (raw is! List) return const <String>[];
      return raw
          .map((value) => value?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toList();
    }

    return CommunityCatalogFilters(
      categories: readList(json['categories']),
      studios: readList(json['studios']),
    );
  }
}

String? _nullable(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int _readInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _readDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
