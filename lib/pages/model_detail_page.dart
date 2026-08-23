import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/catalog_model.dart';
import '../services/cagalog_scanner.dart';
import 'pending_models_page.dart';

class ModelDetailsPage extends StatefulWidget {
  final CatalogModel model;

  final String studioName;

  final String fabulariumPath;

  const ModelDetailsPage({
    super.key,
    required this.model,
    required this.studioName,
    required this.fabulariumPath,
  });

  @override
  State<ModelDetailsPage> createState() =>
      _ModelDetailsPageState();
}

class _ModelDetailsPageState
    extends State<ModelDetailsPage> {
  final CatalogScanner _scanner =
      CatalogScanner();

  late CatalogModel _model;

  int _selectedImage = 0;

  String? _extractingFilePath;

  bool _isExtractingAll = false;

  bool _isRefreshingModel = false;

  @override
  void initState() {
    super.initState();

    _model = widget.model;
  }

  Future<void> _editModel() async {
    final result =
        await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ModelConfigFormPage(
          folderPath:
              _model.folderPath,
          existingConfig:
              _model.config,
        ),
      ),
    );

    if (result == true && mounted) {
      await _reloadCurrentModel();
    }
  }

  Future<void> _reloadCurrentModel() async {
    if (_isRefreshingModel) {
      return;
    }

    setState(() {
      _isRefreshingModel = true;
    });

    try {
      final studios =
          await _scanner.scan(
        widget.fabulariumPath,
      );

      CatalogModel? updatedModel;

      for (final studio in studios) {
        for (final model in studio.models) {
          if (p.normalize(
                model.folderPath,
              ) ==
              p.normalize(
                _model.folderPath,
              )) {
            updatedModel = model;
            break;
          }
        }

        if (updatedModel != null) {
          break;
        }
      }

      if (!mounted) {
        return;
      }

      if (updatedModel != null) {
        setState(() {
          _model = updatedModel!;
          _selectedImage = 0;
        });
      } else {
        _showMessage(
          'The model could not be found after the update.',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Error updating model:\n$e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingModel = false;
        });
      }
    }
  }

  Future<void> _openFolder() async {
    final directory =
        Directory(_model.folderPath);

    if (!await directory.exists()) {
      return;
    }

    await Process.run(
      'explorer.exe',
      [
        directory.path,
      ],
    );
  }

  Future<String> _getDownloadsPath() async {
    final userProfile =
        Platform.environment['USERPROFILE'];

    if (userProfile == null ||
        userProfile.isEmpty) {
      throw Exception(
        'Could not determine the Windows user folder.',
      );
    }

    final downloads =
        Directory(
      p.join(
        userProfile,
        'Downloads',
      ),
    );

    if (!await downloads.exists()) {
      await downloads.create(
        recursive: true,
      );
    }

    return downloads.path;
  }

  String _sanitizeFolderName(
    String value,
  ) {
    var result = value.trim();

    if (result.isEmpty) {
      result = 'Model';
    }

    result = result.replaceAll(
      RegExp(r'[<>:"/\\|?*]'),
      '_',
    );

    return result;
  }

  Future<Directory>
      _getModelDownloadDirectory() async {
    final downloadsPath =
        await _getDownloadsPath();

    final modelName =
        _sanitizeFolderName(
      _model.name,
    );

    final directory =
        Directory(
      p.join(
        downloadsPath,
        modelName,
      ),
    );

    await directory.create(
      recursive: true,
    );

    return directory;
  }

  Future<void> _extractArchive(
    File archive,
  ) async {
    if (_extractingFilePath != null ||
        _isExtractingAll) {
      return;
    }

    setState(() {
      _extractingFilePath =
          archive.path;
    });

    try {
      final modelDirectory =
          await _getModelDownloadDirectory();

      final archiveName =
          p.basenameWithoutExtension(
        archive.path,
      );

      final destination =
          Directory(
        p.join(
          modelDirectory.path,
          _sanitizeFolderName(
            archiveName,
          ),
        ),
      );

      await destination.create(
        recursive: true,
      );

      await _extractWith7Zip(
        archive,
        destination,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _extractingFilePath = null;
      });

      await _askToOpenFolder(
        destination,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _extractingFilePath = null;
      });

      _showMessage(
        'Error extracting file:\n$e',
        isError: true,
      );
    }
  }

  Future<void> _extractAllArchives() async {
    final archives =
        _model.archiveFiles;

    if (archives.isEmpty) {
      _showMessage(
        'No archive files were found.',
      );

      return;
    }

    setState(() {
      _isExtractingAll = true;
    });

    try {
      final modelDirectory =
          await _getModelDownloadDirectory();

      for (final archive in archives) {
        final archiveName =
            p.basenameWithoutExtension(
          archive.path,
        );

        final destination =
            Directory(
          p.join(
            modelDirectory.path,
            _sanitizeFolderName(
              archiveName,
            ),
          ),
        );

        await destination.create(
          recursive: true,
        );

        await _extractWith7Zip(
          archive,
          destination,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _isExtractingAll = false;
      });

      await _askToOpenFolder(
        modelDirectory,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isExtractingAll = false;
      });

      _showMessage(
        'Error extracting files:\n$e',
        isError: true,
      );
    }
  }

  Future<void> _extractWith7Zip(
    File archive,
    Directory destination,
  ) async {
    final sevenZip =
        await _find7Zip();

    if (sevenZip == null) {
      throw Exception(
        '7-Zip was not found on this computer.\n\n'
        'Please install 7-Zip and try again.',
      );
    }

    final result = await Process.run(
      sevenZip,
      [
        'x',
        '-y',
        archive.path,
        '-o${destination.path}',
      ],
      runInShell: true,
    );

    if (result.exitCode != 0) {
      throw Exception(
        '7-Zip could not extract:\n'
        '${p.basename(archive.path)}\n\n'
        '${result.stderr}',
      );
    }
  }

  Future<String?> _find7Zip() async {
    final programFiles =
        Platform.environment[
            'ProgramFiles'];

    final programFilesX86 =
        Platform.environment[
            'ProgramFiles(x86)'];

    final localAppData =
        Platform.environment[
            'LOCALAPPDATA'];

    final possiblePaths =
        <String>[
      if (programFiles != null)
        p.join(
          programFiles,
          '7-Zip',
          '7z.exe',
        ),
      if (programFilesX86 != null)
        p.join(
          programFilesX86,
          '7-Zip',
          '7z.exe',
        ),
      if (localAppData != null)
        p.join(
          localAppData,
          'Programs',
          '7-Zip',
          '7z.exe',
        ),
    ];

    for (final path in possiblePaths) {
      if (await File(path).exists()) {
        return path;
      }
    }

    final result = await Process.run(
      'where',
      ['7z.exe'],
      runInShell: true,
    );

    if (result.exitCode == 0) {
      final output =
          result.stdout.toString().trim();

      if (output.isNotEmpty) {
        final paths = output.split(
          RegExp(r'\r?\n'),
        );

        for (final path in paths) {
          final cleanPath =
              path.trim();

          if (cleanPath.isNotEmpty &&
              await File(
                cleanPath,
              ).exists()) {
            return cleanPath;
          }
        }
      }
    }

    return null;
  }

  Future<void> _askToOpenFolder(
    Directory directory,
  ) async {
    if (!mounted) {
      return;
    }

    final shouldOpen =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Extraction Completed',
          ),
          content: const Text(
            'The files were extracted successfully.\n\n'
            'Would you like to open the destination folder?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(
                context,
              ).pop(false),
              child: const Text(
                'No',
              ),
            ),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(
                context,
              ).pop(true),
              icon: const Icon(
                Icons.folder_open,
              ),
              label: const Text(
                'Open Folder',
              ),
            ),
          ],
        );
      },
    );

    if (shouldOpen == true) {
      await Process.run(
        'explorer.exe',
        [
          directory.path,
        ],
      );
    }
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context)
                .colorScheme
                .error
            : null,
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _model.name,
        ),
        actions: [
          if (_isRefreshingModel)
            const Padding(
              padding:
                  EdgeInsets.symmetric(
                horizontal: 16,
              ),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child:
                      CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip:
                'Open Model Folder',
            icon: const Icon(
              Icons.folder_open_outlined,
            ),
            onPressed:
                _openFolder,
          ),
          IconButton(
            tooltip: 'Edit Model',
            icon: const Icon(
              Icons.edit_outlined,
            ),
            onPressed:
                _isRefreshingModel
                    ? null
                    : _editModel,
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: _buildGallery(),
          ),
          Expanded(
            flex: 2,
            child:
                _buildInformation(),
          ),
        ],
      ),
    );
  }

  Widget _buildGallery() {
    final images =
        _model.images;

    if (images.isEmpty) {
      return const Center(
        child: Icon(
          Icons.image_outlined,
          size: 80,
        ),
      );
    }

    if (_selectedImage >=
        images.length) {
      _selectedImage = 0;
    }

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding:
                const EdgeInsets.all(
              24,
            ),
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(
                12,
              ),
              child: Image.file(
                images[_selectedImage],
                fit: BoxFit.contain,
                width:
                    double.infinity,
                errorBuilder:
                    (
                  context,
                  error,
                  stackTrace,
                ) {
                  return const Center(
                    child: Icon(
                      Icons
                          .broken_image_outlined,
                      size: 80,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (images.length > 1)
          SizedBox(
            height: 110,
            child: ListView.builder(
              scrollDirection:
                  Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 8,
              ),
              itemCount:
                  images.length,
              itemBuilder:
                  (context, index) {
                final selected =
                    index ==
                        _selectedImage;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedImage =
                          index;
                    });
                  },
                  child: Container(
                    width: 90,
                    margin:
                        const EdgeInsets.only(
                      right: 12,
                    ),
                    decoration:
                        BoxDecoration(
                      borderRadius:
                          BorderRadius
                              .circular(
                        8,
                      ),
                      border: Border.all(
                        width:
                            selected
                                ? 3
                                : 1,
                        color: selected
                            ? Theme.of(
                                context,
                              )
                                .colorScheme
                                .primary
                            : Theme.of(
                                context,
                              )
                                .dividerColor,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius
                              .circular(
                        6,
                      ),
                      child: Image.file(
                        images[index],
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildInformation() {
    final model = _model;

    return SingleChildScrollView(
      padding:
          const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            model.name,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(
                  fontWeight:
                      FontWeight.bold,
                ),
          ),
          const SizedBox(
            height: 8,
          ),
          Text(
            model.studio,
            style: Theme.of(context)
                .textTheme
                .titleMedium,
          ),
          const SizedBox(
            height: 32,
          ),
          _InfoRow(
            label: 'Studio',
            value: model.studio,
          ),
          _InfoRow(
            label: 'Category',
            value: model.category,
          ),
          _InfoRow(
            label: 'Type',
            value:
                _typeLabel(
              model.type,
            ),
          ),
          _InfoRow(
            label: 'Scale',
            value: model.scale,
          ),
          _InfoRow(
            label: 'Height',
            value: model.height,
          ),
          const SizedBox(
            height: 16,
          ),
          if (model.tags.isNotEmpty) ...[
            Text(
              'Tags',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(
                    fontWeight:
                        FontWeight.bold,
                  ),
            ),
            const SizedBox(
              height: 8,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  model.tags.map(
                (tag) {
                  return Chip(
                    label:
                        Text(tag),
                  );
                },
              ).toList(),
            ),
          ],
          const SizedBox(
            height: 24,
          ),
          if (model.description
              .isNotEmpty) ...[
            Text(
              'Description',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(
                    fontWeight:
                        FontWeight.bold,
                  ),
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              model.description,
            ),
          ],
          const SizedBox(
            height: 32,
          ),
          if (model.archiveFiles
              .isNotEmpty)
            _buildArchivesSection(),
          const SizedBox(
            height: 24,
          ),
          SizedBox(
            width:
                double.infinity,
            child:
                FilledButton.icon(
              onPressed:
                  _isRefreshingModel
                      ? null
                      : _editModel,
              icon: const Icon(
                Icons.edit_outlined,
              ),
              label: const Text(
                'Edit Model',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchivesSection() {
    final archives =
        _model.archiveFiles;

    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.archive_outlined,
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: Text(
                    'Available Files',
                    style: Theme.of(
                      context,
                    )
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          fontWeight:
                              FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 12,
            ),
            ...archives.map(
              (archive) =>
                  _buildArchiveItem(
                archive,
              ),
            ),
            const SizedBox(
              height: 12,
            ),
            SizedBox(
              width:
                  double.infinity,
              child:
                  FilledButton.icon(
                onPressed:
                    _isExtractingAll ||
                            _extractingFilePath !=
                                null
                        ? null
                        : _extractAllArchives,
                icon:
                    _isExtractingAll
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(
                              strokeWidth:
                                  2,
                            ),
                          )
                        : const Icon(
                            Icons
                                .download_outlined,
                          ),
                label: Text(
                  _isExtractingAll
                      ? 'Extracting All...'
                      : 'Extract All to Downloads',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArchiveItem(
    File archive,
  ) {
    final extension =
        p.extension(
      archive.path,
    ).toLowerCase();

    final isExtracting =
        _extractingFilePath ==
            archive.path;

    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 8,
      ),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(
          8,
        ),
        border: Border.all(
          color: Theme.of(context)
              .dividerColor,
        ),
      ),
      child: ListTile(
        leading: Icon(
          _archiveIcon(
            extension,
          ),
        ),
        title: Text(
          p.basename(
            archive.path,
          ),
          maxLines: 2,
          overflow:
              TextOverflow.ellipsis,
        ),
        subtitle: Text(
          extension
              .replaceFirst(
                '.',
                '',
              )
              .toUpperCase(),
        ),
        trailing:
            FilledButton.icon(
          onPressed:
              isExtracting ||
                      _isExtractingAll
                  ? null
                  : () =>
                      _extractArchive(
                    archive,
                  ),
          icon: isExtracting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Icon(
                  Icons
                      .download_outlined,
                ),
          label: Text(
            isExtracting
                ? 'Extracting...'
                : 'Extract',
          ),
        ),
      ),
    );
  }

  IconData _archiveIcon(
    String extension,
  ) {
    switch (extension) {
      case '.rar':
        return Icons
            .folder_zip_outlined;
      case '.7z':
        return Icons
            .inventory_2_outlined;
      case '.zip':
      default:
        return Icons.folder_zip;
    }
  }

  String _typeLabel(
    String type,
  ) {
    switch (type.toLowerCase()) {
      case 'statue':
        return 'Statue';
      case 'bust':
        return 'Bust';
      case 'miniature':
        return 'Miniature';
      case 'diorama':
        return 'Diorama';
      default:
        return type;
    }
  }
}

class _InfoRow
    extends StatelessWidget {
  final String label;

  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    if (value.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 14,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}