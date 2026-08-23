import 'dart:io';

class CatalogModel {
  final String folderPath;

  final String name;

  final String studio;

  final String category;

  final String type;

  final String scale;

  final String height;

  final List<String> tags;

  final String description;

  final List<File> images;

  final List<File> archiveFiles;

  final Map<String, dynamic> config;

  const CatalogModel({
    required this.folderPath,
    required this.name,
    required this.studio,
    required this.category,
    required this.type,
    required this.scale,
    required this.height,
    required this.tags,
    required this.description,
    required this.images,
    required this.archiveFiles,
    required this.config,
  });
}

class CatalogStudio {
  final String name;

  final List<CatalogModel> models;

  const CatalogStudio({
    required this.name,
    required this.models,
  });
}