import 'package:flutter/material.dart';

import '../config/fabularium_config.dart';
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
import '../widgets/catalog_model_card.dart';
import 'telegram_storage_settings_page.dart';

class TelegramStorageUploadPage extends StatefulWidget {
  const TelegramStorageUploadPage({super.key});
  @override
  State<TelegramStorageUploadPage> createState() => _TelegramStorageUploadPageState();
}

class _TelegramStorageUploadPageState extends State<TelegramStorageUploadPage> {
  final CatalogScanner _scanner = CatalogScanner();
  final CatalogModelIdentityService _identity = CatalogModelIdentityService.instance;
  final TelegramStorageWorkspaceService _workspaceService = TelegramStorageWorkspaceService.instance;
  final TelegramStoragePackager _packager = TelegramStoragePackager.instance;
  final TelegramStoragePackageRecoveryService _recovery = TelegramStoragePackageRecoveryService.instance;
  final TelegramStoragePackageUploader _uploader = TelegramStoragePackageUploader.instance;
  final TelegramStorageModelRegistryService _registry = TelegramStorageModelRegistryService.instance;
  final TextEditingController _search = TextEditingController();

  TelegramStorageWorkspace _workspace = const TelegramStorageWorkspace.empty();
  List<CatalogStudio> _studios = const [];
  bool _loading = true;
  bool _busy = false;
  CatalogModel? _active;
  String _stage = '';
  double _progress = 0;
  String? _error;

  @override
  void initState() { super.initState(); _load(); _search.addListener(() => setState(() {})); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _workspaceService.load(),
        _scanner.scan(FabulariumConfig.rootPath),
      ]);
      if (!mounted) return;
      setState(() { _workspace = results[0] as TelegramStorageWorkspace; _studios = results[1] as List<CatalogStudio>; _loading = false; });
    } catch (e) { if (mounted) setState(() { _loading = false; _error = e.toString(); }); }
  }

  Iterable<(CatalogModel, String)> get _models sync* {
    final q = _search.text.trim().toLowerCase();
    for (final studio in _studios) {
      for (final model in studio.models) {
        if (q.isEmpty || '${model.name} ${model.studio} ${model.category} ${model.tags.join(' ')}'.toLowerCase().contains(q)) {
          yield (model, studio.name);
        }
      }
    }
  }

  Future<void> _upload(CatalogModel model) async {
    if (_busy) return;
    if (!_workspace.isFullyConfigured) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TelegramStorageSettingsPage()));
      _workspace = await _workspaceService.load();
      if (!_workspace.isFullyConfigured || !mounted) return;
    }
    setState(() { _busy = true; _active = model; _progress = 0; _stage = 'Preparing package...'; _error = null; });
    try {
      final modelId = await _identity.ensureModelId(model);
      var package = await _packager.prepareFolder(
        folderPath: model.folderPath,
        onProgress: (value, stage) { if (mounted) setState(() { _progress = value * 0.35; _stage = stage; }); },
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
            modelId: modelId,
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
      await _registry.linkPackage(model: model, modelId: modelId, packageId: package.packageId);
      bool synced = false;
      await _uploader.uploadPackage(
        workspace: _workspace,
        package: package,
        onProgress: (p) {
          if (!mounted) return;
          if (!synced) { synced = true; }
          setState(() { _progress = 0.35 + p.overallProgress * 0.65; _stage = p.stage; });
        },
      );
      if (mounted) setState(() { _progress = 1; _stage = 'Stored successfully.'; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _stage = 'Upload interrupted. Use Upload Recovery.'; });
    } finally {
      if (mounted) setState(() { _busy = false; _active = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final models = _models.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Models'), actions: [IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: TextField(controller: _search, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search models...', border: OutlineInputBorder())),
              ),
              if (_busy || _stage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(_active == null ? _stage : '${_active!.name} — $_stage'),
                    const SizedBox(height: 6), LinearProgressIndicator(value: _progress),
                    if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  ]),
                ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 320, childAspectRatio: 0.72, crossAxisSpacing: 16, mainAxisSpacing: 16),
                  itemCount: models.length,
                  itemBuilder: (_, i) => CatalogModelCard(
                    model: models[i].$1,
                    studioName: models[i].$2,
                    showStudio: true,
                    actionLabel: _active == models[i].$1 ? 'Uploading...' : 'Upload',
                    actionIcon: Icons.cloud_upload_outlined,
                    onTap: _busy ? null : () => _upload(models[i].$1),
                  ),
                ),
              ),
            ]),
    );
  }
}
