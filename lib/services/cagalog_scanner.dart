import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/catalog_model.dart';

class CatalogScanner {
  static const Set<String> _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
  static const Set<String> _archiveExtensions = {'.zip', '.rar', '.7z'};

  Future<List<CatalogStudio>> scan(String fabulariumPath) async {
    final stlDirectory = Directory(p.join(fabulariumPath, 'Files', 'STL'));
    if (!await stlDirectory.exists()) {
      throw Exception('The STL folder was not found:\n${stlDirectory.path}');
    }
    final studioDirectories = await stlDirectory
        .list(recursive: false, followLinks: false)
        .where((entity) => entity is Directory)
        .cast<Directory>()
        .toList();
    studioDirectories.sort((a, b) => p
        .basename(a.path)
        .toLowerCase()
        .compareTo(p.basename(b.path).toLowerCase()));

    final studios = <CatalogStudio>[];
    for (final studioDirectory in studioDirectories) {
      final models = <CatalogModel>[];
      await _scanForModels(
        directory: studioDirectory,
        studioName: p.basename(studioDirectory.path),
        models: models,
      );
      models.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (models.isNotEmpty) {
        studios.add(CatalogStudio(
          name: p.basename(studioDirectory.path),
          models: models,
        ));
      }
    }
    return studios;
  }

  Future<void> _scanForModels({
    required Directory directory,
    required String studioName,
    required List<CatalogModel> models,
  }) async {
    final configFile = File(p.join(directory.path, 'config.json'));
    if (await configFile.exists()) {
      final model = await _readModel(
        directory: directory,
        studioName: studioName,
        configFile: configFile,
      );
      if (model != null) models.add(model);
      return;
    }
    final entities = await directory.list(recursive: false, followLinks: false).toList();
    final directories = entities.whereType<Directory>().toList()
      ..sort((a, b) => p
          .basename(a.path)
          .toLowerCase()
          .compareTo(p.basename(b.path).toLowerCase()));
    for (final childDirectory in directories) {
      await _scanForModels(
        directory: childDirectory,
        studioName: studioName,
        models: models,
      );
    }
  }

  Future<CatalogModel?> _readModel({
    required Directory directory,
    required String studioName,
    required File configFile,
  }) async {
    try {
      final decoded = jsonDecode(await configFile.readAsString());
      if (decoded is! Map) return null;
      final config = Map<String, dynamic>.from(decoded);
      final images = <File>[];
      final archiveFiles = <File>[];
      final entities = await directory.list(recursive: true, followLinks: false).toList();
      for (final entity in entities) {
        if (entity is! File) continue;
        final extension = p.extension(entity.path).toLowerCase();
        if (_imageExtensions.contains(extension)) images.add(entity);
        if (_archiveExtensions.contains(extension)) archiveFiles.add(entity);
      }
      images.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      archiveFiles.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      return CatalogModel(
        folderPath: directory.path,
        name: _stringValue(config['name'], fallback: p.basename(directory.path)),
        studio: _stringValue(config['studio'], fallback: studioName),
        category: _stringValue(config['category']),
        type: _stringValue(config['type']),
        scale: _stringValue(config['scale']),
        height: _stringValue(config['height']),
        tags: _stringList(config['tags']),
        description: _stringValue(config['description']),
        images: images,
        archiveFiles: archiveFiles,
        config: config,
      );
    } catch (_) {
      return null;
    }
  }

  String _stringValue(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final result = value.toString();
    return result.trim().isEmpty ? fallback : result;
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return <String>[];
    return value.map((item) => item.toString()).where((item) => item.isNotEmpty).toList();
  }
}
