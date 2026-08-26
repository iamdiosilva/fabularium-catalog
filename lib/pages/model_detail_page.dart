import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/catalog_model.dart';
import '../models/telegram_storage_package.dart';
import '../models/telegram_storage_workspace.dart';
import '../services/cagalog_scanner.dart';
import '../services/catalog_model_identity_service.dart';
import '../services/telegram_storage_model_registry_service.dart';
import '../services/telegram_storage_package_recovery_service.dart';
import '../services/telegram_storage_package_uploader.dart';
import '../services/telegram_storage_packager.dart';
import '../services/telegram_storage_workspace_service.dart';
import 'pending_models_page.dart';
import 'telegram_storage_recovery_page.dart';
import 'telegram_storage_settings_page.dart';

class ModelDetailsPage
    extends StatefulWidget {
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
  State<ModelDetailsPage>
      createState() =>
          _ModelDetailsPageState();
}

class _ModelDetailsPageState
    extends State<ModelDetailsPage> {
  final CatalogScanner _scanner =
      CatalogScanner();

  final CatalogModelIdentityService
      _identityService =
      CatalogModelIdentityService.instance;

  final TelegramStorageWorkspaceService
      _workspaceService =
      TelegramStorageWorkspaceService.instance;

  final TelegramStoragePackager _storagePackager =
      TelegramStoragePackager.instance;

  final TelegramStoragePackageRecoveryService
      _packageRecoveryService =
      TelegramStoragePackageRecoveryService.instance;

  final TelegramStoragePackageUploader
      _packageUploader =
      TelegramStoragePackageUploader.instance;

  final TelegramStorageModelRegistryService
      _storageRegistry =
      TelegramStorageModelRegistryService.instance;

  late CatalogModel _model;

  TelegramStorageWorkspace _storageWorkspace =
      const TelegramStorageWorkspace.empty();

  TelegramStorageModelStatus? _storageStatus;

  String _modelId =
      '';

  int _selectedImage =
      0;

  String? _extractingFilePath;

  bool _isExtractingAll =
      false;

  bool _isRefreshingModel =
      false;

  bool _isLoadingStorage =
      true;

  bool _isStorageBusy =
      false;

  double _storageProgress =
      0;

  String _storageStage =
      '';

  String? _storageError;

  @override
  void initState() {
    super.initState();

    _model =
        widget.model;

    _loadStorageState();
  }

  Future<void> _editModel() async {
    final result =
        await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder:
            (_) =>
                ModelConfigFormPage(
          folderPath:
              _model.folderPath,
          existingConfig:
              _model.config,
        ),
      ),
    );

    if (result ==
            true &&
        mounted) {
      await _reloadCurrentModel();
    }
  }

  Future<void> _reloadCurrentModel() async {
    if (_isRefreshingModel) {
      return;
    }

    setState(() {
      _isRefreshingModel =
          true;
    });

    try {
      final studios =
          await _scanner.scan(
        widget.fabulariumPath,
      );

      CatalogModel? updatedModel;

      for (final studio
          in studios) {
        for (final model
            in studio.models) {
          if (p.normalize(
                model.folderPath,
              ) ==
              p.normalize(
                _model.folderPath,
              )) {
            updatedModel =
                model;

            break;
          }
        }

        if (updatedModel !=
            null) {
          break;
        }
      }

      if (!mounted) {
        return;
      }

      if (updatedModel !=
          null) {
        setState(() {
          _model =
              updatedModel!;
          _selectedImage =
              0;
        });

        await _loadStorageState(
          showLoading:
              false,
        );
      } else {
        _showMessage(
          'The model could not be found after the update.',
          isError:
              true,
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Error updating model:\n$e',
        isError:
            true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingModel =
              false;
        });
      }
    }
  }

  // ============================================================
  // TELEGRAM STORAGE
  // ============================================================

  Future<void> _loadStorageState({
    bool showLoading = true,
  }) async {
    if (!mounted) {
      return;
    }

    if (showLoading) {
      setState(() {
        _isLoadingStorage =
            true;
        _storageError =
            null;
      });
    }

    try {
      final workspace =
          await _workspaceService.load();

      final modelId =
          await _identityService.ensureModelId(
        _model,
      );

      if (_model.config['modelId'] !=
          modelId) {
        _model =
            CatalogModel(
          folderPath:
              _model.folderPath,
          name:
              _model.name,
          studio:
              _model.studio,
          category:
              _model.category,
          type:
              _model.type,
          scale:
              _model.scale,
          height:
              _model.height,
          tags:
              _model.tags,
          description:
              _model.description,
          images:
              _model.images,
          archiveFiles:
              _model.archiveFiles,
          config:
              <String, dynamic>{
            ..._model.config,
            'modelId':
                modelId,
          },
        );
      }

      final status =
          await _storageRegistry.getStatus(
        model:
            _model,
        modelId:
            modelId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _storageWorkspace =
            workspace;
        _storageStatus =
            status;
        _modelId =
            modelId;
        _isLoadingStorage =
            false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingStorage =
            false;
        _storageError =
            e.toString();
      });
    }
  }

  Future<void> _openStorageSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) =>
                const TelegramStorageSettingsPage(),
      ),
    );

    await _loadStorageState();
  }

  Future<void> _openStorageRecovery() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) =>
                const TelegramStorageRecoveryPage(),
      ),
    );

    await _loadStorageState();
  }

  Future<void> _uploadModelToTelegram() async {
    if (_isStorageBusy) {
      return;
    }

    final status =
        _storageStatus;

    if (status?.isStored ==
        true) {
      _showMessage(
        'This model already has a STORED Telegram package.',
      );

      return;
    }

    if (status?.isIncomplete ==
        true) {
      _showMessage(
        'This model already has an incomplete Telegram upload. '
        'Use Upload Recovery to Resume or Clean it.',
      );

      return;
    }

    if (!_storageWorkspace
        .isFullyConfigured) {
      await _openStorageSettings();

      return;
    }

    final confirmed =
        await showDialog<bool>(
      context:
          context,
      builder:
          (
        context,
      ) {
        return AlertDialog(
          title:
              const Text(
            'Upload Model to Telegram?',
          ),
          content:
              Text(
            '${_model.name}\n\n'
            'Local images: ${_model.images.length}\n'
            'Local archives: ${_model.archiveFiles.length}\n\n'
            'Catalog → ${_storageWorkspace.catalogChannel!.title}\n'
            'Files → ${_storageWorkspace.filesChannel!.title}\n\n'
            'Fabularium will prepare the Storage V3 package and '
            'start the upload immediately.',
          ),
          actions: [
            TextButton(
              onPressed:
                  () {
                Navigator.of(
                  context,
                ).pop(
                  false,
                );
              },
              child:
                  const Text(
                'Cancel',
              ),
            ),
            FilledButton.icon(
              onPressed:
                  () {
                Navigator.of(
                  context,
                ).pop(
                  true,
                );
              },
              icon:
                  const Icon(
                Icons.cloud_upload_outlined,
              ),
              label:
                  const Text(
                'Upload',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed !=
            true ||
        !mounted) {
      return;
    }

    setState(() {
      _isStorageBusy =
          true;
      _storageProgress =
          0;
      _storageStage =
          'Preparing Storage V3 package...';
      _storageError =
          null;
    });

    TelegramStoragePackage? package;

    try {
      package =
          await _storagePackager
              .prepareFolder(
        folderPath:
            _model.folderPath,
        onProgress:
            (
          progress,
          stage,
        ) {
          if (!mounted) {
            return;
          }

          setState(() {
            _storageProgress =
                progress *
                0.35;
            _storageStage =
                stage;
          });
        },
      );

      package =
          _attachModelIdToPackage(
        package,
        _modelId,
      );

      await _packageRecoveryService
          .savePackage(
        package,
      );

      await _storageRegistry
          .linkPackage(
        model:
            _model,
        modelId:
            _modelId,
        packageId:
            package.packageId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _storageProgress =
            0.35;
        _storageStage =
            'Starting Telegram upload...';
      });

      final result =
          await _packageUploader
              .uploadPackage(
        workspace:
            _storageWorkspace,
        package:
            package,
        onProgress:
            (
          progress,
        ) {
          if (!mounted) {
            return;
          }

          setState(() {
            _storageProgress =
                0.35 +
                (
                  progress.overallProgress *
                  0.65
                );
            _storageStage =
                progress.stage;
          });
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _storageProgress =
            1;
        _storageStage =
            'Stored in Telegram.';
      });

      await _loadStorageState(
        showLoading:
            false,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        result.alreadyUploaded
            ? 'The model was already stored. Nothing was duplicated.'
            : 'Model stored successfully. Manifest message ID: '
                '${result.manifestMessageId}.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _storageError =
            e.toString();
        _storageStage =
            'Upload interrupted.';
      });

      await _loadStorageState(
        showLoading:
            false,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Telegram Storage upload interrupted. '
        'The package can be continued from Upload Recovery.',
        isError:
            true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isStorageBusy =
              false;
        });
      }
    }
  }

  TelegramStoragePackage _attachModelIdToPackage(
    TelegramStoragePackage package,
    String modelId,
  ) {
    final catalog =
        package.catalog;

    final updatedCatalog =
        catalog ==
                null
            ? null
            : TelegramStorageCatalogInfo(
                modelId:
                    modelId,
                name:
                    catalog.name,
                studio:
                    catalog.studio,
                category:
                    catalog.category,
                type:
                    catalog.type,
                scale:
                    catalog.scale,
                height:
                    catalog.height,
                description:
                    catalog.description,
                tags:
                    catalog.tags,
                galleryImagePaths:
                    catalog.galleryImagePaths,
              );

    return TelegramStoragePackage(
      packageId:
          package.packageId,
      sourceFolderName:
          package.sourceFolderName,
      sourceFolderPath:
          package.sourceFolderPath,
      sourceSize:
          package.sourceSize,
      archiveFileName:
          package.archiveFileName,
      archiveSize:
          package.archiveSize,
      archiveSha256:
          package.archiveSha256,
      stagingDirectoryPath:
          package.stagingDirectoryPath,
      manifestPath:
          package.manifestPath,
      createdAt:
          package.createdAt,
      parts:
          package.parts,
      catalog:
          updatedCatalog,
    );
  }

  String _storageStatusDescription() {
    final status =
        _storageStatus;

    if (status ==
        null) {
      return 'Checking Storage V3 status...';
    }

    if (status.journal ==
        null) {
      return 'This local model does not have a Telegram Storage package.';
    }

    if (status.journal!.isStored) {
      return 'A completed Storage V3 package is recorded for this model.';
    }

    if (status.journal!.isFailed) {
      return 'The last Storage V3 upload failed and can be resumed or cleaned.';
    }

    if (status.journal!.isUploading) {
      return 'This model has an upload journal currently marked as UPLOADING.';
    }

    if (status.journal!.isPreparing) {
      return 'This model has a package waiting in PREPARING state.';
    }

    if (status.journal!.isRemoving) {
      return 'This model is currently being removed by Clean.';
    }

    return 'Storage V3 status available.';
  }

  String _formatStorageDate(
    DateTime value,
  ) {
    final local =
        value.toLocal();

    String two(
      int value,
    ) =>
        value
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '${two(local.day)}/'
        '${two(local.month)}/'
        '${local.year} '
        '${two(local.hour)}:'
        '${two(local.minute)}';
  }

  // ============================================================
  // LOCAL FILE ACTIONS
  // ============================================================

  Future<void> _openFolder() async {
    final directory =
        Directory(
      _model.folderPath,
    );

    if (!await directory.exists()) {
      return;
    }

    await Process.run(
      'explorer.exe',
      <String>[
        directory.path,
      ],
    );
  }

  Future<String> _getDownloadsPath() async {
    final userProfile =
        Platform.environment[
            'USERPROFILE'];

    if (userProfile ==
            null ||
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
        recursive:
            true,
      );
    }

    return downloads.path;
  }

  String _sanitizeFolderName(
    String value,
  ) {
    var result =
        value.trim();

    if (result.isEmpty) {
      result =
          'Model';
    }

    result =
        result.replaceAll(
      RegExp(
        r'[<>:"/\\|?*]',
      ),
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
      recursive:
          true,
    );

    return directory;
  }

  Future<void> _extractArchive(
    File archive,
  ) async {
    if (_extractingFilePath !=
            null ||
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
        recursive:
            true,
      );

      await _extractWith7Zip(
        archive,
        destination,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _extractingFilePath =
            null;
      });

      await _askToOpenFolder(
        destination,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _extractingFilePath =
            null;
      });

      _showMessage(
        'Error extracting file:\n$e',
        isError:
            true,
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
      _isExtractingAll =
          true;
    });

    try {
      final modelDirectory =
          await _getModelDownloadDirectory();

      for (final archive
          in archives) {
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
          recursive:
              true,
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
        _isExtractingAll =
            false;
      });

      await _askToOpenFolder(
        modelDirectory,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isExtractingAll =
            false;
      });

      _showMessage(
        'Error extracting files:\n$e',
        isError:
            true,
      );
    }
  }

  Future<void> _extractWith7Zip(
    File archive,
    Directory destination,
  ) async {
    final sevenZip =
        await _find7Zip();

    if (sevenZip ==
        null) {
      throw Exception(
        '7-Zip was not found on this computer.\n\n'
        'Please install 7-Zip and try again.',
      );
    }

    if (!await archive.exists()) {
      throw Exception(
        'The archive file was not found:\n'
        '${archive.path}',
      );
    }

    await destination.create(
      recursive:
          true,
    );

    final archivePath =
        p.normalize(
      archive.path,
    );

    final destinationPath =
        p.normalize(
      destination.path,
    );

    final result =
        await Process.run(
      sevenZip,
      <String>[
        'x',
        archivePath,
        '-o$destinationPath',
        '-y',
        '-aoa',
      ],
      runInShell:
          false,
    );

    final stdout =
        result.stdout
            .toString()
            .trim();

    final stderr =
        result.stderr
            .toString()
            .trim();

    if (result.exitCode !=
        0) {
      final details =
          stderr.isNotEmpty
              ? stderr
              : stdout;

      throw Exception(
        '7-Zip could not extract:\n'
        '${p.basename(archive.path)}\n\n'
        'Exit code: ${result.exitCode}\n'
        '$details',
      );
    }

    if (!_hasExtractedFiles(
      destination,
    )) {
      throw Exception(
        '7-Zip completed the operation, '
        'but no files were found in the destination folder.\n\n'
        'Archive:\n'
        '${archive.path}',
      );
    }
  }

  bool _hasExtractedFiles(
    Directory directory,
  ) {
    try {
      final files =
          directory
              .listSync(
                recursive:
                    true,
                followLinks:
                    false,
              )
              .whereType<File>();

      return files.isNotEmpty;
    } catch (_) {
      return false;
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
      if (programFiles !=
          null)
        p.join(
          programFiles,
          '7-Zip',
          '7z.exe',
        ),
      if (programFilesX86 !=
          null)
        p.join(
          programFilesX86,
          '7-Zip',
          '7z.exe',
        ),
      if (localAppData !=
          null)
        p.join(
          localAppData,
          'Programs',
          '7-Zip',
          '7z.exe',
        ),
    ];

    for (final path
        in possiblePaths) {
      if (await File(
        path,
      ).exists()) {
        return path;
      }
    }

    final result =
        await Process.run(
      'where',
      <String>[
        '7z.exe',
      ],
      runInShell:
          true,
    );

    if (result.exitCode ==
        0) {
      final output =
          result.stdout
              .toString()
              .trim();

      if (output.isNotEmpty) {
        final paths =
            output.split(
          RegExp(
            r'\r?\n',
          ),
        );

        for (final path
            in paths) {
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
      context:
          context,
      builder:
          (
        context,
      ) {
        return AlertDialog(
          title:
              const Text(
            'Extraction Completed',
          ),
          content:
              const Text(
            'The files were extracted successfully.\n\n'
            'Would you like to open the destination folder?',
          ),
          actions: [
            TextButton(
              onPressed:
                  () =>
                      Navigator.of(
                context,
              ).pop(
                false,
              ),
              child:
                  const Text(
                'No',
              ),
            ),
            FilledButton.icon(
              onPressed:
                  () =>
                      Navigator.of(
                context,
              ).pop(
                true,
              ),
              icon:
                  const Icon(
                Icons.folder_open,
              ),
              label:
                  const Text(
                'Open Folder',
              ),
            ),
          ],
        );
      },
    );

    if (shouldOpen ==
        true) {
      await Process.run(
        'explorer.exe',
        <String>[
          directory.path,
        ],
      );
    }
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content:
            Text(
          message,
        ),
        backgroundColor:
            isError
                ? Theme.of(
                    context,
                  )
                    .colorScheme
                    .error
                : null,
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar:
          AppBar(
        title:
            Text(
          _model.name,
        ),
        actions: [
          if (_isRefreshingModel)
            const Padding(
              padding:
                  EdgeInsets.symmetric(
                horizontal:
                    16,
              ),
              child:
                  Center(
                child:
                    SizedBox(
                  width:
                      20,
                  height:
                      20,
                  child:
                      CircularProgressIndicator(
                    strokeWidth:
                        2,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip:
                'Refresh Storage Status',
            onPressed:
                _isStorageBusy
                    ? null
                    : _loadStorageState,
            icon:
                const Icon(
              Icons.cloud_sync_outlined,
            ),
          ),
          IconButton(
            tooltip:
                'Open Model Folder',
            icon:
                const Icon(
              Icons.folder_open_outlined,
            ),
            onPressed:
                _openFolder,
          ),
          IconButton(
            tooltip:
                'Edit Model',
            icon:
                const Icon(
              Icons.edit_outlined,
            ),
            onPressed:
                _isRefreshingModel ||
                        _isLoadingStorage
                    ? null
                    : _editModel,
          ),
        ],
      ),
      body:
          Row(
        children: [
          Expanded(
            flex:
                3,
            child:
                _buildGallery(),
          ),
          Expanded(
            flex:
                2,
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
        child:
            Icon(
          Icons.image_outlined,
          size:
              80,
        ),
      );
    }

    if (_selectedImage >=
        images.length) {
      _selectedImage =
          0;
    }

    return Column(
      children: [
        Expanded(
          child:
              Padding(
            padding:
                const EdgeInsets.all(
              24,
            ),
            child:
                ClipRRect(
              borderRadius:
                  BorderRadius.circular(
                12,
              ),
              child:
                  Image.file(
                images[
                    _selectedImage],
                fit:
                    BoxFit.contain,
                width:
                    double.infinity,
                errorBuilder:
                    (
                  context,
                  error,
                  stackTrace,
                ) {
                  return const Center(
                    child:
                        Icon(
                      Icons.broken_image_outlined,
                      size:
                          80,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (images.length >
            1)
          SizedBox(
            height:
                110,
            child:
                ListView.builder(
              scrollDirection:
                  Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(
                horizontal:
                    24,
                vertical:
                    8,
              ),
              itemCount:
                  images.length,
              itemBuilder:
                  (
                context,
                index,
              ) {
                final selected =
                    index ==
                    _selectedImage;

                return GestureDetector(
                  onTap:
                      () {
                    setState(() {
                      _selectedImage =
                          index;
                    });
                  },
                  child:
                      Container(
                    width:
                        90,
                    margin:
                        const EdgeInsets.only(
                      right:
                          12,
                    ),
                    decoration:
                        BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(
                        8,
                      ),
                      border:
                          Border.all(
                        width:
                            selected
                                ? 3
                                : 1,
                        color:
                            selected
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
                    child:
                        ClipRRect(
                      borderRadius:
                          BorderRadius.circular(
                        6,
                      ),
                      child:
                          Image.file(
                        images[
                            index],
                        fit:
                            BoxFit.cover,
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
    final model =
        _model;

    return SingleChildScrollView(
      padding:
          const EdgeInsets.all(
        32,
      ),
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            model.name,
            style:
                Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(
                      fontWeight:
                          FontWeight.bold,
                    ),
          ),
          const SizedBox(
            height:
                8,
          ),
          Text(
            model.studio,
            style:
                Theme.of(context)
                    .textTheme
                    .titleMedium,
          ),
          const SizedBox(
            height:
                32,
          ),
          _InfoRow(
            label:
                'Studio',
            value:
                model.studio,
          ),
          _InfoRow(
            label:
                'Category',
            value:
                model.category,
          ),
          _InfoRow(
            label:
                'Type',
            value:
                _typeLabel(
              model.type,
            ),
          ),
          _InfoRow(
            label:
                'Scale',
            value:
                model.scale,
          ),
          _InfoRow(
            label:
                'Height',
            value:
                model.height,
          ),
          const SizedBox(
            height:
                16,
          ),
          if (model.tags
              .isNotEmpty) ...[
            Text(
              'Tags',
              style:
                  Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(
                        fontWeight:
                            FontWeight.bold,
                      ),
            ),
            const SizedBox(
              height:
                  8,
            ),
            Wrap(
              spacing:
                  8,
              runSpacing:
                  8,
              children:
                  model.tags
                      .map(
                        (
                          tag,
                        ) =>
                            Chip(
                          label:
                              Text(
                            tag,
                          ),
                        ),
                      )
                      .toList(),
            ),
          ],
          const SizedBox(
            height:
                24,
          ),
          if (model.description
              .isNotEmpty) ...[
            Text(
              'Description',
              style:
                  Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(
                        fontWeight:
                            FontWeight.bold,
                      ),
            ),
            const SizedBox(
              height:
                  8,
            ),
            Text(
              model.description,
            ),
          ],
          const SizedBox(
            height:
                32,
          ),
          _buildStorageSection(),
          const SizedBox(
            height:
                24,
          ),
          if (model.archiveFiles
              .isNotEmpty)
            _buildArchivesSection(),
          const SizedBox(
            height:
                24,
          ),
          SizedBox(
            width:
                double.infinity,
            child:
                FilledButton.icon(
              onPressed:
                  _isRefreshingModel ||
                          _isLoadingStorage
                      ? null
                      : _editModel,
              icon:
                  const Icon(
                Icons.edit_outlined,
              ),
              label:
                  const Text(
                'Edit Model',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageSection() {
    final status =
        _storageStatus;

    final journal =
        status?.journal;

    return Card(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          18,
        ),
        child:
            Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.cloud_outlined,
                ),
                const SizedBox(
                  width:
                      10,
                ),
                Expanded(
                  child:
                      Text(
                    'Telegram Storage',
                    style:
                        Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                  ),
                ),
                if (_isLoadingStorage)
                  const SizedBox(
                    width:
                        18,
                    height:
                        18,
                    child:
                        CircularProgressIndicator(
                      strokeWidth:
                          2,
                    ),
                  )
                else
                  Chip(
                    label:
                        Text(
                      status
                              ?.telegramStatusLabel ??
                          'UNKNOWN',
                    ),
                  ),
              ],
            ),
            const SizedBox(
              height:
                  12,
            ),
            Text(
              _storageStatusDescription(),
            ),
            const SizedBox(
              height:
                  14,
            ),
            _StorageInfoRow(
              label:
                  'Local',
              value:
                  status?.localAvailable ==
                          false
                      ? 'Missing'
                      : 'Available',
              icon:
                  status?.localAvailable ==
                          false
                      ? Icons.folder_off_outlined
                      : Icons.folder_outlined,
            ),
            _StorageInfoRow(
              label:
                  'Images',
              value:
                  '${_model.images.length}',
              icon:
                  Icons.photo_library_outlined,
            ),
            _StorageInfoRow(
              label:
                  'Archives',
              value:
                  '${_model.archiveFiles.length}',
              icon:
                  Icons.archive_outlined,
            ),
            if (_modelId.isNotEmpty) ...[
              const SizedBox(
                height:
                    6,
              ),
              SelectableText(
                'Model ID: $_modelId',
                style:
                    Theme.of(context)
                        .textTheme
                        .bodySmall,
              ),
            ],
            if (journal !=
                null) ...[
              const Divider(
                height:
                    24,
              ),
              SelectableText(
                'Package ID: ${journal.packageId}',
                style:
                    Theme.of(context)
                        .textTheme
                        .bodySmall,
              ),
              const SizedBox(
                height:
                    8,
              ),
              Wrap(
                spacing:
                    16,
                runSpacing:
                    8,
                children: [
                  Text(
                    'Gallery: ${journal.galleryMessageIds.length}',
                  ),
                  Text(
                    'File groups: ${journal.fileGroups.length}',
                  ),
                  Text(
                    'Manifest: ${journal.manifestMessageId ?? '-'}',
                  ),
                ],
              ),
              const SizedBox(
                height:
                    8,
              ),
              Text(
                'Updated: ${_formatStorageDate(journal.updatedAt)}',
                style:
                    Theme.of(context)
                        .textTheme
                        .bodySmall,
              ),
              if (journal.lastError !=
                      null &&
                  journal.lastError!
                      .trim()
                      .isNotEmpty) ...[
                const SizedBox(
                  height:
                      10,
                ),
                Text(
                  journal.lastError!,
                  style:
                      TextStyle(
                    color:
                        Theme.of(context)
                            .colorScheme
                            .error,
                  ),
                ),
              ],
            ],
            if (_isStorageBusy) ...[
              const SizedBox(
                height:
                    16,
              ),
              Text(
                _storageStage,
                style:
                    const TextStyle(
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
              const SizedBox(
                height:
                    8,
              ),
              LinearProgressIndicator(
                value:
                    _storageProgress,
              ),
              const SizedBox(
                height:
                    6,
              ),
              Text(
                '${(_storageProgress * 100).toStringAsFixed(0)}%',
              ),
            ],
            if (_storageError !=
                null) ...[
              const SizedBox(
                height:
                    12,
              ),
              Text(
                _storageError!,
                style:
                    TextStyle(
                  color:
                      Theme.of(context)
                          .colorScheme
                          .error,
                ),
              ),
            ],
            const SizedBox(
              height:
                  16,
            ),
            Wrap(
              spacing:
                  10,
              runSpacing:
                  10,
              children: [
                if (!_storageWorkspace
                    .isFullyConfigured)
                  FilledButton.tonalIcon(
                    onPressed:
                        _isStorageBusy
                            ? null
                            : _openStorageSettings,
                    icon:
                        const Icon(
                      Icons.settings_outlined,
                    ),
                    label:
                        const Text(
                      'Configure Storage',
                    ),
                  )
                else if (status?.journal ==
                    null)
                  FilledButton.icon(
                    onPressed:
                        _isStorageBusy
                            ? null
                            : _uploadModelToTelegram,
                    icon:
                        const Icon(
                      Icons.cloud_upload_outlined,
                    ),
                    label:
                        const Text(
                      'Upload to Telegram',
                    ),
                  )
                else if (status!.isIncomplete)
                  FilledButton.tonalIcon(
                    onPressed:
                        _isStorageBusy
                            ? null
                            : _openStorageRecovery,
                    icon:
                        const Icon(
                      Icons.restore_outlined,
                    ),
                    label:
                        const Text(
                      'Open Recovery',
                    ),
                  )
                else if (status.isStored)
                  const Chip(
                    avatar:
                        Icon(
                      Icons.cloud_done_outlined,
                      size:
                          18,
                    ),
                    label:
                        Text(
                      'Stored in Telegram',
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed:
                      _isStorageBusy
                          ? null
                          : _loadStorageState,
                  icon:
                      const Icon(
                    Icons.refresh,
                  ),
                  label:
                      const Text(
                    'Refresh Status',
                  ),
                ),
              ],
            ),
            const SizedBox(
              height:
                  12,
            ),
            Text(
              'modelId is persistent in this model config.json and is also '
              'stored in new Telegram manifests. Upload uses four concurrent '
              '512 KB Telegram parts. Repair will later verify message IDs '
              'directly against Telegram.',
              style:
                  Theme.of(context)
                      .textTheme
                      .bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArchivesSection() {
    final archives =
        _model.archiveFiles;

    return Card(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          16,
        ),
        child:
            Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.archive_outlined,
                ),
                const SizedBox(
                  width:
                      10,
                ),
                Expanded(
                  child:
                      Text(
                    'Available Files',
                    style:
                        Theme.of(context)
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
              height:
                  12,
            ),
            ...archives.map(
              (
                archive,
              ) =>
                  _buildArchiveItem(
                archive,
              ),
            ),
            const SizedBox(
              height:
                  12,
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
                            width:
                                18,
                            height:
                                18,
                            child:
                                CircularProgressIndicator(
                              strokeWidth:
                                  2,
                            ),
                          )
                        : const Icon(
                            Icons.download_outlined,
                          ),
                label:
                    Text(
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
        bottom:
            8,
      ),
      decoration:
          BoxDecoration(
        borderRadius:
            BorderRadius.circular(
          8,
        ),
        border:
            Border.all(
          color:
              Theme.of(context)
                  .dividerColor,
        ),
      ),
      child:
          ListTile(
        leading:
            Icon(
          _archiveIcon(
            extension,
          ),
        ),
        title:
            Text(
          p.basename(
            archive.path,
          ),
          maxLines:
              2,
          overflow:
              TextOverflow.ellipsis,
        ),
        subtitle:
            Text(
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
          icon:
              isExtracting
                  ? const SizedBox(
                      width:
                          16,
                      height:
                          16,
                      child:
                          CircularProgressIndicator(
                        strokeWidth:
                            2,
                      ),
                    )
                  : const Icon(
                      Icons.download_outlined,
                    ),
          label:
              Text(
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
        return Icons.folder_zip_outlined;

      case '.7z':
        return Icons.inventory_2_outlined;

      case '.zip':
      default:
        return Icons.folder_zip;
    }
  }

  String _typeLabel(
    String type,
  ) {
    switch (
        type.toLowerCase()) {
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
        bottom:
            14,
      ),
      child:
          Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width:
                100,
            child:
                Text(
              label,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child:
                Text(
              value,
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageInfoRow
    extends StatelessWidget {
  final String label;

  final String value;

  final IconData icon;

  const _StorageInfoRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom:
            8,
      ),
      child:
          Row(
        children: [
          Icon(
            icon,
            size:
                18,
          ),
          const SizedBox(
            width:
                8,
          ),
          SizedBox(
            width:
                72,
            child:
                Text(
              label,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child:
                Text(
              value,
            ),
          ),
        ],
      ),
    );
  }
}
