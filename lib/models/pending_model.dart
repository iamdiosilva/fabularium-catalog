import 'dart:io';

class PendingModel {
  final String folderPath;
  final String folderName;
  final String studioName;
  final List<File> images;
  final List<File> archiveFiles;

  const PendingModel({
    required this.folderPath,
    required this.folderName,
    required this.studioName,
    required this.images,
    required this.archiveFiles,
  });
}
