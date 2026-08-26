import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/catalog_model.dart';
import '../models/telegram_storage_package.dart';
import '../models/telegram_storage_workspace.dart';
import '../services/catalog_model_identity_service.dart';
import '../services/telegram_storage_model_registry_service.dart';
import '../services/telegram_storage_package_recovery_service.dart';
import '../services/telegram_storage_package_uploader.dart';
import '../services/telegram_storage_packager.dart';
import '../services/telegram_storage_verification_service.dart';
import '../services/telegram_storage_workspace_service.dart';
import 'pending_models_page.dart';
import 'telegram_storage_recovery_page.dart';
import 'telegram_storage_settings_page.dart';

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
  State<ModelDetailsPage> createState() => _ModelDetailsPageState();
}

class _ModelDetailsPageState extends State<ModelDetailsPage> {
  final CatalogModelIdentityService _identity =
      CatalogModelIdentityService.instance;
  final TelegramStorageWorkspaceService _workspaceService =
      TelegramStorageWorkspaceService.instance;
  final TelegramStorageModelRegistryService _registry =
      TelegramStorageModelRegistryService.instance;
  final TelegramStorageVerificationService _verification =
      TelegramStorageVerificationService.instance;
  final TelegramStoragePackager _packager = TelegramStoragePackager.instance;
  final TelegramStoragePackageRecoveryService _recovery =
      TelegramStoragePackageRecoveryService.instance;
  final TelegramStoragePackageUploader _uploader =
      TelegramStoragePackageUploader.instance;

  late CatalogModel _model;
  TelegramStorageWorkspace _workspace =
      const TelegramStorageWorkspace.empty();
  TelegramStorageModelStatus? _status;
  String _modelId = '';
  bool _loadingStatus = true;
  bool _hasLoadedStorageState = false;
  bool _busy = false;
  bool _verified = false;
  bool _verificationUnavailable = false;
  int _selectedImage = 0;
  double _progress = 0;
  String _stage = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _model = widget.model;
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    if (mounted) {
      setState(() {
        _loadingStatus = true;
        _error = null;

        // Keep the last known Telegram state while refreshing.
        // This prevents the UI from briefly falling back to an empty
        // workspace and showing actions such as Configure Storage.
        if (!_busy) {
          _stage = '';
          _progress = 0;
        }
      });
    }

    try {
      final workspace = await _workspaceService.load();
      final modelId = await _identity.ensureModelId(_model);
      var status = await _registry.getStatus(
        model: _model,
        modelId: modelId,
      );

      var verified = false;
      var verificationUnavailable = false;

      if (status.journal?.isStored == true) {
        try {
          final result = await _verification.verifyAndUpdate(
            journal: status.journal!,
          );

          verified = result.allPresent;

          if (!result.allPresent) {
            status = await _registry.getStatus(
              model: _model,
              modelId: modelId,
            );
          }
        } catch (_) {
          verificationUnavailable = true;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace = workspace;
        _modelId = modelId;
        _status = status;
        _verified = verified;
        _verificationUnavailable = verificationUnavailable;
        _loadingStatus = false;
        _hasLoadedStorageState = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingStatus = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _edit() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ModelConfigFormPage(
          folderPath: _model.folderPath,
          existingConfig: _model.config,
        ),
      ),
    );

    if (result == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _upload() async {
    if (_busy) {
      return;
    }

    if (!_workspace.isFullyConfigured) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const TelegramStorageSettingsPage(),
        ),
      );
      await _loadStatus();
      return;
    }

    if (_status?.journal != null) {
      if (_status!.isStored) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This model is already stored in Telegram.'),
          ),
        );
      } else {
        await _openRecovery();
      }
      return;
    }

    setState(() {
      _busy = true;
      _progress = 0;
      _stage = 'Preparing package...';
      _error = null;
    });

    try {
      var package = await _packager.prepareFolder(
        folderPath: _model.folderPath,
        onProgress: (value, stage) {
          if (!mounted) {
            return;
          }

          setState(() {
            _progress = value * 0.35;
            _stage = stage;
          });
        },
      );

      final catalog = package.catalog;

      if (catalog != null) {
        package = TelegramStoragePackage(
          packageId: package.packageId,
          sourceFolderName: package.sourceFolderName,
          sourceFolderPath: package.sourceFolderPath,
          sourceSize: package.sourceSize,
          archiveFileName: package.archiveFileName,
          archiveSize: package.archiveSize,
          archiveSha256: package.archiveSha256,
          stagingDirectoryPath: package.stagingDirectoryPath,
          manifestPath: package.manifestPath,
          createdAt: package.createdAt,
          parts: package.parts,
          catalog: TelegramStorageCatalogInfo(
            modelId: _modelId,
            name: catalog.name,
            studio: catalog.studio,
            category: catalog.category,
            type: catalog.type,
            scale: catalog.scale,
            height: catalog.height,
            description: catalog.description,
            tags: catalog.tags,
            galleryImagePaths: catalog.galleryImagePaths,
          ),
        );
      }

      await _recovery.savePackage(package);

      await _registry.linkPackage(
        model: _model,
        modelId: _modelId,
        packageId: package.packageId,
      );

      bool journalSynced = false;

      await _uploader.uploadPackage(
        workspace: _workspace,
        package: package,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }

          if (!journalSynced) {
            journalSynced = true;
            unawaited(_refreshLocalStatus());
          }

          setState(() {
            _progress = 0.35 + progress.overallProgress * 0.65;
            _stage = progress.stage;
          });
        },
      );

      if (mounted) {
        setState(() {
          _progress = 1;
          _stage = 'Stored successfully.';
        });
      }

      await _loadStatus();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _stage = 'Upload interrupted. Open Recovery to continue.';
        });
      }

      await _refreshLocalStatus();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _refreshLocalStatus() async {
    if (_modelId.isEmpty) {
      return;
    }

    try {
      final value = await _registry.getStatus(
        model: _model,
        modelId: _modelId,
      );

      if (mounted) {
        setState(() {
          _status = value;
        });
      }
    } catch (_) {}
  }

  Future<void> _openRecovery() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const TelegramStorageRecoveryPage(),
      ),
    );

    await _loadStatus();
  }

  Future<void> _extract(File archive) async {
    try {
      final sevenZip = await _find7Zip();

      if (sevenZip == null) {
        throw Exception('7-Zip was not found.');
      }

      final user = Platform.environment['USERPROFILE'];

      if (user == null) {
        throw Exception('Windows user profile was not found.');
      }

      final destination = Directory(
        p.join(
          user,
          'Downloads',
          _safeName(_model.name),
          _safeName(p.basenameWithoutExtension(archive.path)),
        ),
      );

      await destination.create(recursive: true);

      final result = await Process.run(
        sevenZip,
        [
          'x',
          archive.path,
          '-o${destination.path}',
          '-y',
          '-aoa',
        ],
      );

      if (result.exitCode != 0) {
        throw Exception(
          result.stderr.toString().trim().isEmpty
              ? result.stdout.toString()
              : result.stderr.toString(),
        );
      }

      await Process.start(
        'explorer.exe',
        [destination.path],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
          ),
        );
      }
    }
  }

  Future<String?> _find7Zip() async {
    final candidates = [
      r'C:\Program Files\7-Zip\7z.exe',
      r'C:\Program Files (x86)\7-Zip\7z.exe',
    ];

    for (final value in candidates) {
      if (await File(value).exists()) {
        return value;
      }
    }

    try {
      final result = await Process.run(
        'where',
        ['7z.exe'],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        return result.stdout
            .toString()
            .split(RegExp(r'[\r\n]+'))
            .first
            .trim();
      }
    } catch (_) {}

    return null;
  }

  String _safeName(String value) {
    return value.replaceAll(
      RegExp(r'[<>:"/\\|?*]'),
      '_',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_model.name),
        actions: [
          IconButton(
            tooltip: 'Refresh Storage Status',
            onPressed: _busy || _loadingStatus ? null : _loadStatus,
            icon: const Icon(Icons.cloud_sync_outlined),
          ),
          IconButton(
            tooltip: 'Open Folder',
            onPressed: () => Process.start(
              'explorer.exe',
              [_model.folderPath],
            ),
            icon: const Icon(Icons.folder_open_outlined),
          ),
          IconButton(
            tooltip: 'Edit Model',
            onPressed: _busy || _loadingStatus ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: _gallery(),
          ),
          Expanded(
            flex: 2,
            child: ListView(
              padding: const EdgeInsets.all(28),
              children: [
                Text(
                  _model.name,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  _model.studio,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 22),
                _info('Category', _model.category),
                _info('Type', _model.type),
                _info('Scale', _model.scale),
                _info('Height', _model.height),
                if (_model.tags.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _model.tags
                        .map(
                          (tag) => Chip(label: Text(tag)),
                        )
                        .toList(),
                  ),
                if (_model.description.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Description',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(_model.description),
                ],
                const SizedBox(height: 22),
                _storageCard(),
                if (_model.archiveFiles.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _archiveCard(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gallery() {
    if (_model.images.isEmpty) {
      return const Center(
        child: Icon(
          Icons.image_outlined,
          size: 80,
        ),
      );
    }

    if (_selectedImage >= _model.images.length) {
      _selectedImage = 0;
    }

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Image.file(
              _model.images[_selectedImage],
              fit: BoxFit.contain,
            ),
          ),
        ),
        if (_model.images.length > 1)
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              itemCount: _model.images.length,
              itemBuilder: (_, index) {
                final selected = index == _selectedImage;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedImage = index;
                    });
                  },
                  child: Container(
                    width: 84,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        width: selected ? 3 : 1,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).dividerColor,
                      ),
                    ),
                    child: Image.file(
                      _model.images[index],
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _info(String label, String value) {
    if (value.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  String get _statusLabel {
    if (_loadingStatus && !_hasLoadedStorageState) {
      return 'LOADING';
    }

    if (_busy) {
      return 'UPLOADING';
    }

    if (_verification.isRemoteMissingJournal(_status?.journal)) {
      return 'TELEGRAM INCOMPLETE';
    }

    final journal = _status?.journal;

    if (journal == null) {
      return 'NOT UPLOADED';
    }

    if (journal.isStored && _verified) {
      return 'UPLOADED · VERIFIED';
    }

    if (journal.isStored && _verificationUnavailable) {
      return 'UPLOADED · UNCHECKED';
    }

    return journal.status.name.toUpperCase();
  }

  Widget _storageCard() {
    if (!_hasLoadedStorageState) {
      if (_loadingStatus) {
        return _buildStorageLoadingCard();
      }

      if (_error != null) {
        return _buildStorageLoadErrorCard();
      }
    }

    final journal = _status?.journal;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Telegram Storage',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (_loadingStatus && _hasLoadedStorageState) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Chip(
                  label: Text(_statusLabel),
                ),
              ],
            ),
            if (_modelId.isNotEmpty)
              SelectableText(
                'Model ID: $_modelId',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (journal != null) ...[
              const SizedBox(height: 6),
              SelectableText(
                'Package ID: ${journal.packageId}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Gallery: ${journal.galleryMessageIds.length} '
                '• File groups: ${journal.fileGroups.length} '
                '• Manifest: ${journal.manifestMessageId ?? '-'}',
              ),
            ],

            // Progress is visible only while there is an active operation.
            // A LinearProgressIndicator with value == null is indeterminate,
            // which was the cause of the endless loading after a successful
            // verification/upload.
            if (_busy) ...[
              const SizedBox(height: 12),
              if (_stage.isNotEmpty) ...[
                Text(_stage),
                const SizedBox(height: 6),
              ],
              LinearProgressIndicator(
                value: _progress.clamp(0.0, 1.0).toDouble(),
              ),
            ] else if (_stage.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_stage),
            ],

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (!_workspace.isFullyConfigured)
                  FilledButton.tonalIcon(
                    onPressed: _busy || _loadingStatus
                        ? null
                        : () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const TelegramStorageSettingsPage(),
                              ),
                            );
                            await _loadStatus();
                          },
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Configure Storage'),
                  )
                else if (journal == null)
                  FilledButton.icon(
                    onPressed: _busy || _loadingStatus ? null : _upload,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Upload to Telegram'),
                  )
                else if (!journal.isStored)
                  FilledButton.tonalIcon(
                    onPressed: _busy || _loadingStatus ? null : _openRecovery,
                    icon: const Icon(Icons.restore_outlined),
                    label: const Text('Open Recovery'),
                  )
                else
                  const Chip(
                    avatar: Icon(
                      Icons.cloud_done_outlined,
                      size: 18,
                    ),
                    label: Text('Stored in Telegram'),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy || _loadingStatus ? null : _loadStatus,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Status'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageLoadingCard() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_outlined),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Telegram Storage',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              ],
            ),
            SizedBox(height: 14),
            Text('Loading Telegram Storage...'),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageLoadErrorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cloud_off_outlined),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Telegram Storage',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Could not load Telegram Storage status.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadingStatus ? null : _loadStatus,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _archiveCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Available Files',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._model.archiveFiles.map(
              (file) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_zip_outlined),
                title: Text(p.basename(file.path)),
                trailing: FilledButton.tonalIcon(
                  onPressed: () => _extract(file),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Extract'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
