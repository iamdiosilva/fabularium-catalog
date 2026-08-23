import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/pending_model.dart';

class PendingModelScanner {
  static const imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
  };

  static const archiveExtensions = {
    '.zip',
    '.rar',
  };

  Future<List<PendingModel>> scan(
    String fabulariumPath,
  ) async {
    final stlDirectory = Directory(
      p.join(
        fabulariumPath,
        'Files',
        'STL',
      ),
    );

    if (!await stlDirectory.exists()) {
      throw Exception(
        'The STL folder was not found.',
      );
    }

    final studios = await stlDirectory
        .list(
          recursive: false,
          followLinks: false,
        )
        .where(
          (entity) => entity is Directory,
        )
        .cast<Directory>()
        .toList();

    studios.sort(
      (a, b) => p
          .basename(a.path)
          .toLowerCase()
          .compareTo(
            p.basename(b.path).toLowerCase(),
          ),
    );

    final pendingModels = <PendingModel>[];

    for (final studioDirectory in studios) {
      await _scanDirectory(
        directory: studioDirectory,
        studioName: p.basename(
          studioDirectory.path,
        ),
        pendingModels: pendingModels,
      );
    }

    pendingModels.sort(
      (a, b) {
        final studioComparison = a.studioName
            .toLowerCase()
            .compareTo(
              b.studioName.toLowerCase(),
            );

        if (studioComparison != 0) {
          return studioComparison;
        }

        return a.folderName
            .toLowerCase()
            .compareTo(
              b.folderName.toLowerCase(),
            );
      },
    );

    return pendingModels;
  }

  Future<void> _scanDirectory({
    required Directory directory,
    required String studioName,
    required List<PendingModel> pendingModels,
  }) async {
    final configFile = File(
      p.join(
        directory.path,
        'config.json',
      ),
    );

    // The model is already registered.
    if (await configFile.exists()) {
      return;
    }

    final entities = await directory
        .list(
          recursive: false,
          followLinks: false,
        )
        .toList();

    final images = <File>[];
    final archives = <File>[];
    final directories = <Directory>[];

    for (final entity in entities) {
      if (entity is File) {
        final extension =
            p.extension(entity.path).toLowerCase();

        if (imageExtensions.contains(extension)) {
          images.add(entity);
        }

        if (archiveExtensions.contains(extension)) {
          archives.add(entity);
        }
      } else if (entity is Directory) {
        directories.add(entity);
      }
    }

    // If the folder contains images or archives,
    // consider it a model folder.
    if (images.isNotEmpty || archives.isNotEmpty) {
      pendingModels.add(
        PendingModel(
          folderPath: directory.path,
          folderName: p.basename(directory.path),
          studioName: studioName,
          images: images,
          archiveFiles: archives,
        ),
      );

      return;
    }

    directories.sort(
      (a, b) => p
          .basename(a.path)
          .toLowerCase()
          .compareTo(
            p.basename(b.path).toLowerCase(),
          ),
    );

    for (final childDirectory in directories) {
      await _scanDirectory(
        directory: childDirectory,
        studioName: studioName,
        pendingModels: pendingModels,
      );
    }
  }
}