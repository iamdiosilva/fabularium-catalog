import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class CatalogSuggestions {
  final List<String> categories;
  final List<String> scales;
  final List<String> tags;

  const CatalogSuggestions({
    required this.categories,
    required this.scales,
    required this.tags,
  });

  const CatalogSuggestions.empty()
      : categories = const [],
        scales = const [],
        tags = const [];
}

class CatalogSuggestionsService {
  Future<CatalogSuggestions> load(
    String folderPath,
  ) async {
    final stlDirectory = _findStlDirectory(
      folderPath,
    );

    if (stlDirectory == null ||
        !await stlDirectory.exists()) {
      return const CatalogSuggestions.empty();
    }

    final categories = <String>{};
    final scales = <String>{};
    final tags = <String>{};

    try {
      await for (final entity in stlDirectory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File ||
            p.basename(entity.path).toLowerCase() !=
                'config.json') {
          continue;
        }

        try {
          final content =
              await entity.readAsString();

          final decoded =
              jsonDecode(content);

          if (decoded is! Map) {
            continue;
          }

          final config =
              Map<String, dynamic>.from(
            decoded,
          );

          _addValue(
            categories,
            config['category'],
          );

          _addValue(
            scales,
            config['scale'],
          );

          final configTags =
              config['tags'];

          if (configTags is List) {
            for (final tag in configTags) {
              _addValue(
                tags,
                tag,
              );
            }
          }
        } catch (_) {
          // Ignore invalid config files and continue
          // reading the remaining models.
        }
      }
    } catch (_) {
      return const CatalogSuggestions.empty();
    }

    return CatalogSuggestions(
      categories: _sortValues(
        categories,
      ),
      scales: _sortValues(
        scales,
      ),
      tags: _sortValues(
        tags,
      ),
    );
  }

  Directory? _findStlDirectory(
    String folderPath,
  ) {
    var current =
        Directory(folderPath);

    while (true) {
      final currentName =
          p.basename(current.path)
              .toLowerCase();

      if (currentName == 'stl') {
        return current;
      }

      final parent =
          current.parent;

      if (parent.path == current.path) {
        break;
      }

      current = parent;
    }

    return null;
  }

  void _addValue(
    Set<String> values,
    dynamic value,
  ) {
    if (value == null) {
      return;
    }

    final text =
        value.toString().trim();

    if (text.isEmpty) {
      return;
    }

    final alreadyExists =
        values.any(
      (item) =>
          item.toLowerCase() ==
          text.toLowerCase(),
    );

    if (!alreadyExists) {
      values.add(text);
    }
  }

  List<String> _sortValues(
    Set<String> values,
  ) {
    final result =
        values.toList();

    result.sort(
      (a, b) => a
          .toLowerCase()
          .compareTo(
            b.toLowerCase(),
          ),
    );

    return result;
  }
}