import 'package:flutter/material.dart';

import '../config/fabularium_config.dart';
import '../models/catalog_model.dart';
import '../models/telegram_storage_package.dart';
import '../models/telegram_storage_workspace.dart';
import '../services/cagalog_scanner.dart';
import '../services/telegram_storage_package_recovery_service.dart';
import '../services/telegram_storage_package_uploader.dart';
import '../services/telegram_storage_packager.dart';
import '../services/telegram_storage_workspace_service.dart';
import '../widgets/catalog_model_card.dart';
import 'telegram_storage_settings_page.dart';

class TelegramStorageUploadPage
    extends StatefulWidget {
  const TelegramStorageUploadPage({
    super.key,
  });

  @override
  State<TelegramStorageUploadPage>
      createState() =>
          _TelegramStorageUploadPageState();
}

class _TelegramStorageUploadPageState
    extends State<TelegramStorageUploadPage> {
  final CatalogScanner _scanner =
      CatalogScanner();

  final TelegramStorageWorkspaceService
      _workspaceService =
      TelegramStorageWorkspaceService.instance;

  final TelegramStoragePackager _packager =
      TelegramStoragePackager.instance;

  final TelegramStoragePackageUploader
      _packageUploader =
      TelegramStoragePackageUploader.instance;

  final TelegramStoragePackageRecoveryService
      _packageRecoveryService =
      TelegramStoragePackageRecoveryService.instance;

  final TextEditingController _searchController =
      TextEditingController();

  TelegramStorageWorkspace _workspace =
      const TelegramStorageWorkspace.empty();

  List<CatalogStudio> _studios =
      <CatalogStudio>[];

  String? _selectedStudio;

  String _searchQuery =
      '';

  CatalogModel? _activeModel;

  TelegramStoragePackage? _preparedPackage;

  TelegramStoragePackageUploadResult?
      _lastPackageUpload;

  bool _isLoading =
      true;

  bool _isPackaging =
      false;

  bool _isUploadingPackage =
      false;

  double _packageProgress =
      0;

  double _packageUploadProgress =
      0;

  String _packageStage =
      '';

  String _packageUploadStage =
      '';

  String? _packageUploadFileName;

  String? _error;

  String? _status;

  bool get _isBusy =>
      _isPackaging ||
      _isUploadingPackage;

  @override
  void initState() {
    super.initState();

    _searchController.addListener(
      _onSearchChanged,
    );

    _loadData();
  }

  @override
  void dispose() {
    _searchController.removeListener(
      _onSearchChanged,
    );

    _searchController.dispose();

    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) {
      return;
    }

    setState(() {
      _searchQuery =
          _searchController.text
              .trim();
    });
  }

  Future<void> _loadData() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading =
          true;
      _error =
          null;
    });

    try {
      final workspace =
          await _workspaceService.load();

      final studios =
          await _scanner.scan(
        FabulariumConfig.rootPath,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace =
            workspace;
        _studios =
            studios;

        if (_selectedStudio !=
                null &&
            !_studios.any(
              (
                studio,
              ) =>
                  studio.name ==
                  _selectedStudio,
            )) {
          _selectedStudio =
              null;
        }

        _isLoading =
            false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading =
            false;
        _error =
            e.toString();
      });
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) =>
                const TelegramStorageSettingsPage(),
      ),
    );

    try {
      final workspace =
          await _workspaceService.load();

      if (!mounted) {
        return;
      }

      setState(() {
        _workspace =
            workspace;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error =
            e.toString();
      });
    }
  }

  List<_CatalogUploadItem>
      _visibleModels() {
    final normalizedQuery =
        _normalizeText(
      _searchQuery,
    );

    final items =
        <_CatalogUploadItem>[];

    for (final studio
        in _studios) {
      if (_selectedStudio !=
              null &&
          studio.name !=
              _selectedStudio) {
        continue;
      }

      for (final model
          in studio.models) {
        if (normalizedQuery
            .isNotEmpty) {
          final searchable =
              <String>[
            model.name,
            model.studio,
            studio.name,
            model.category,
            model.type,
            model.scale,
            model.height,
            model.description,
            ...model.tags,
          ].join(
            ' ',
          );

          if (!_normalizeText(
            searchable,
          ).contains(
            normalizedQuery,
          )) {
            continue;
          }
        }

        items.add(
          _CatalogUploadItem(
            model:
                model,
            studioName:
                studio.name,
          ),
        );
      }
    }

    items.sort(
      (
        a,
        b,
      ) =>
          a.model.name
              .toLowerCase()
              .compareTo(
                b.model.name
                    .toLowerCase(),
              ),
    );

    return items;
  }

  String _normalizeText(
    String value,
  ) {
    const accents =
        <String, String>{
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'õ': 'o',
      'ô': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'ñ': 'n',
    };

    var result =
        value
            .toLowerCase()
            .trim();

    accents.forEach(
      (
        accent,
        replacement,
      ) {
        result =
            result.replaceAll(
          accent,
          replacement,
        );
      },
    );

    return result;
  }

  Future<void> _prepareModel(
    CatalogModel model,
  ) async {
    if (_isBusy) {
      return;
    }

    if (!_workspace
        .isFullyConfigured) {
      setState(() {
        _error =
            'Configure both Catalog Channel and Files Channel '
            'before preparing a Storage V3 upload.';
      });

      return;
    }

    setState(() {
      _activeModel =
          model;
      _isPackaging =
          true;
      _packageProgress =
          0;
      _packageStage =
          'Preparing...';
      _preparedPackage =
          null;
      _lastPackageUpload =
          null;
      _error =
          null;
      _status =
          null;
    });

    try {
      final package =
          await _packager.prepareFolder(
        folderPath:
            model.folderPath,
        onProgress:
            (
          progress,
          stage,
        ) {
          if (!mounted) {
            return;
          }

          setState(() {
            _packageProgress =
                progress;
            _packageStage =
                stage;
          });
        },
      );

      await _packageRecoveryService
          .savePackage(
        package,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _preparedPackage =
            package;
        _packageProgress =
            1;
        _packageStage =
            'Package ready.';
        _isPackaging =
            false;
        _status =
            package.isSplit
                ? '${model.name} prepared in ${package.partCount} parts.'
                : '${model.name} prepared as a single ZIP.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isPackaging =
            false;
        _packageProgress =
            0;
        _packageStage =
            '';
        _error =
            e.toString();
      });
    }
  }

  Future<void> _uploadPreparedPackage() async {
    final package =
        _preparedPackage;

    if (!_workspace
            .isFullyConfigured ||
        package ==
            null ||
        _isBusy) {
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
            'Upload Storage Package?',
          ),
          content:
              Text(
            '${package.displayName}\n\n'
            'Gallery images: ${package.galleryImageCount}\n'
            'Storage parts: ${package.partCount}\n'
            'Upload size: ${_formatSize(package.totalUploadSize)}\n\n'
            'Gallery → ${_workspace.catalogChannel!.title}\n'
            'Files → ${_workspace.filesChannel!.title}\n\n'
            'Storage V3 will persist the journal after each '
            'completed step.',
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
      _isUploadingPackage =
          true;
      _packageUploadProgress =
          0;
      _packageUploadStage =
          'Starting package upload...';
      _packageUploadFileName =
          null;
      _lastPackageUpload =
          null;
      _error =
          null;
      _status =
          null;
    });

    try {
      final result =
          await _packageUploader
              .uploadPackage(
        workspace:
            _workspace,
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
            _packageUploadProgress =
                progress.overallProgress;
            _packageUploadStage =
                progress.stage;
            _packageUploadFileName =
                progress.currentFileName;
          });
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isUploadingPackage =
            false;
        _packageUploadProgress =
            1;
        _packageUploadStage =
            'Package stored successfully.';
        _lastPackageUpload =
            result;
        _status =
            result.alreadyUploaded
                ? 'This package was already stored. Nothing was duplicated.'
                : 'Package uploaded successfully. Manifest message ID: '
                    '${result.manifestMessageId}.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isUploadingPackage =
            false;
        _error =
            e.toString();
        _status =
            'Package upload was interrupted. Open Upload Recovery '
            'to resume or clean this package.';
      });
    }
  }

  Future<void> _openPreparedPackage() async {
    final package =
        _preparedPackage;

    if (package ==
        null) {
      return;
    }

    try {
      await _packager
          .openPackageFolder(
        package,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error =
            e.toString();
      });
    }
  }

  Future<void> _deletePreparedPackage() async {
    final package =
        _preparedPackage;

    if (package ==
            null ||
        _isBusy) {
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
            'Delete Prepared Package?',
          ),
          content:
              const Text(
            'The temporary ZIP, parts, manifest and recovery descriptor '
            'will be deleted. The original catalog model and Telegram '
            'messages will not be changed.',
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
            FilledButton(
              onPressed:
                  () {
                Navigator.of(
                  context,
                ).pop(
                  true,
                );
              },
              child:
                  const Text(
                'Delete',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed !=
        true) {
      return;
    }

    try {
      await _packager.deletePackage(
        package,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _preparedPackage =
            null;
        _lastPackageUpload =
            null;
        _activeModel =
            null;
        _status =
            'Prepared package deleted.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error =
            e.toString();
      });
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar:
          AppBar(
        title:
            const Text(
          'Storage Upload',
        ),
        actions: [
          IconButton(
            tooltip:
                'Refresh Catalog',
            onPressed:
                _isBusy
                    ? null
                    : _loadData,
            icon:
                const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body:
          _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    if (_studios.isEmpty &&
        _error !=
            null) {
      return Center(
        child:
            Padding(
          padding:
              const EdgeInsets.all(
            24,
          ),
          child:
              _buildErrorCard(),
        ),
      );
    }

    return Row(
      children: [
        _buildStudioList(),
        Expanded(
          child:
              Column(
            children: [
              _buildHeader(),
              _buildSearchBar(),
              if (!_workspace
                  .isFullyConfigured)
                _buildWorkspaceWarning(),
              if (_isPackaging)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(
                    24,
                    8,
                    24,
                    0,
                  ),
                  child:
                      _buildPackagingProgress(),
                ),
              if (_preparedPackage !=
                  null)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(
                    24,
                    8,
                    24,
                    0,
                  ),
                  child:
                      _buildPreparedPackageCard(
                    _preparedPackage!,
                  ),
                ),
              if (_isUploadingPackage)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(
                    24,
                    8,
                    24,
                    0,
                  ),
                  child:
                      _buildPackageUploadProgress(),
                ),
              if (_lastPackageUpload !=
                  null)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(
                    24,
                    8,
                    24,
                    0,
                  ),
                  child:
                      _buildUploadResultCard(
                    _lastPackageUpload!,
                  ),
                ),
              if (_status !=
                  null)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(
                    24,
                    8,
                    24,
                    0,
                  ),
                  child:
                      _buildStatusCard(),
                ),
              if (_error !=
                  null)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(
                    24,
                    8,
                    24,
                    0,
                  ),
                  child:
                      _buildErrorCard(),
                ),
              const SizedBox(
                height:
                    8,
              ),
              Expanded(
                child:
                    _buildCatalogGrid(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final modelCount =
        _studios.fold<int>(
      0,
      (
        total,
        studio,
      ) =>
          total +
          studio.models.length,
    );

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        24,
        20,
        24,
        0,
      ),
      child:
          Row(
        children: [
          Expanded(
            child:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'Fabularium Catalog',
                  style:
                      Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                            fontWeight:
                                FontWeight.bold,
                          ),
                ),
                const SizedBox(
                  height:
                      4,
                ),
                const Text(
                  'Choose a registered model. The package uses the '
                  'same folder and metadata already loaded by the catalog.',
                ),
              ],
            ),
          ),
          Chip(
            label:
                Text(
              '$modelCount models',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudioList() {
    return Container(
      width:
          260,
      decoration:
          BoxDecoration(
        border:
            Border(
          right:
              BorderSide(
            color:
                Theme.of(context)
                    .dividerColor,
          ),
        ),
      ),
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding:
                const EdgeInsets.all(
              16,
            ),
            child:
                Text(
              'Studios',
              style:
                  Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                        fontWeight:
                            FontWeight.bold,
                      ),
            ),
          ),
          const Divider(
            height:
                1,
          ),
          ListTile(
            selected:
                _selectedStudio ==
                    null,
            leading:
                const Icon(
              Icons.apps_outlined,
            ),
            title:
                const Text(
              'All Models',
            ),
            trailing:
                Text(
              '${_studios.fold<int>(0, (total, studio) => total + studio.models.length)}',
            ),
            onTap:
                () {
              setState(() {
                _selectedStudio =
                    null;
              });
            },
          ),
          const Divider(
            height:
                1,
          ),
          Expanded(
            child:
                ListView.builder(
              itemCount:
                  _studios.length,
              itemBuilder:
                  (
                context,
                index,
              ) {
                final studio =
                    _studios[
                        index];

                final selected =
                    _selectedStudio ==
                        studio.name;

                return ListTile(
                  selected:
                      selected,
                  leading:
                      const Icon(
                    Icons.business_outlined,
                  ),
                  title:
                      Text(
                    studio.name,
                    maxLines:
                        1,
                    overflow:
                        TextOverflow.ellipsis,
                  ),
                  trailing:
                      Text(
                    '${studio.models.length}',
                  ),
                  onTap:
                      () {
                    setState(() {
                      _selectedStudio =
                          studio.name;
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        24,
        16,
        24,
        0,
      ),
      child:
          TextField(
        controller:
            _searchController,
        decoration:
            InputDecoration(
          hintText:
              'Search models, studios, categories or tags...',
          prefixIcon:
              const Icon(
            Icons.search,
          ),
          suffixIcon:
              _searchQuery.isNotEmpty
                  ? IconButton(
                      tooltip:
                          'Clear Search',
                      onPressed:
                          _searchController.clear,
                      icon:
                          const Icon(
                        Icons.clear,
                      ),
                    )
                  : null,
          border:
              const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildWorkspaceWarning() {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        24,
        12,
        24,
        0,
      ),
      child:
          Card(
        child:
            Padding(
          padding:
              const EdgeInsets.all(
            16,
          ),
          child:
              Row(
            children: [
              const Icon(
                Icons.warning_amber_outlined,
              ),
              const SizedBox(
                width:
                    12,
              ),
              const Expanded(
                child:
                    Text(
                  'Storage V3 is not fully configured. '
                  'Configure both channels before preparing an upload.',
                ),
              ),
              const SizedBox(
                width:
                    12,
              ),
              FilledButton.tonalIcon(
                onPressed:
                    _openSettings,
                icon:
                    const Icon(
                  Icons.settings_outlined,
                ),
                label:
                    const Text(
                  'Settings',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCatalogGrid() {
    final items =
        _visibleModels();

    if (items.isEmpty) {
      return const Center(
        child:
            Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_outlined,
              size:
                  64,
            ),
            SizedBox(
              height:
                  16,
            ),
            Text(
              'No models found.',
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding:
          const EdgeInsets.all(
        24,
      ),
      gridDelegate:
          const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent:
            300,
        childAspectRatio:
            0.66,
        crossAxisSpacing:
            20,
        mainAxisSpacing:
            20,
      ),
      itemCount:
          items.length,
      itemBuilder:
          (
        context,
        index,
      ) {
        final item =
            items[
                index];

        return CatalogModelCard(
          model:
              item.model,
          studioName:
              item.studioName,
          showStudio:
              true,
          actionLabel:
              'Prepare for Telegram',
          actionIcon:
              Icons.inventory_2_outlined,
          onTap:
              _isBusy
                  ? null
                  : () =>
                      _prepareModel(
                        item.model,
                      ),
        );
      },
    );
  }

  Widget _buildPackagingProgress() {
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
                  Icons.inventory_2_outlined,
                ),
                const SizedBox(
                  width:
                      10,
                ),
                Expanded(
                  child:
                      Text(
                    _activeModel?.name ??
                        _packageStage,
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${(_packageProgress * 100).toStringAsFixed(0)}%',
                ),
              ],
            ),
            const SizedBox(
              height:
                  10,
            ),
            Text(
              _packageStage,
            ),
            const SizedBox(
              height:
                  10,
            ),
            LinearProgressIndicator(
              value:
                  _packageProgress,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreparedPackageCard(
    TelegramStoragePackage package,
  ) {
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
                  Icons.inventory_2_outlined,
                ),
                const SizedBox(
                  width:
                      10,
                ),
                Expanded(
                  child:
                      Text(
                    package.displayName,
                    style:
                        const TextStyle(
                      fontSize:
                          17,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
                const Chip(
                  label:
                      Text(
                    'Package Ready',
                  ),
                ),
              ],
            ),
            const SizedBox(
              height:
                  12,
            ),
            Wrap(
              spacing:
                  18,
              runSpacing:
                  8,
              children: [
                Text(
                  'Gallery: ${package.galleryImageCount}',
                ),
                Text(
                  'Parts: ${package.partCount}',
                ),
                Text(
                  'ZIP: ${_formatSize(package.archiveSize)}',
                ),
                Text(
                  'Upload: ${_formatSize(package.totalUploadSize)}',
                ),
              ],
            ),
            const SizedBox(
              height:
                  14,
            ),
            Wrap(
              spacing:
                  12,
              runSpacing:
                  12,
              children: [
                FilledButton.icon(
                  onPressed:
                      _isBusy
                          ? null
                          : _uploadPreparedPackage,
                  icon:
                      const Icon(
                    Icons.cloud_upload_outlined,
                  ),
                  label:
                      const Text(
                    'Upload to Telegram',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _openPreparedPackage,
                  icon:
                      const Icon(
                    Icons.folder_open,
                  ),
                  label:
                      const Text(
                    'Open Package Folder',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _isBusy
                          ? null
                          : _deletePreparedPackage,
                  icon:
                      const Icon(
                    Icons.delete_outline,
                  ),
                  label:
                      const Text(
                    'Delete Temporary Package',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackageUploadProgress() {
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
            const Text(
              'Uploading Storage Package',
              style:
                  TextStyle(
                fontSize:
                    17,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            const SizedBox(
              height:
                  8,
            ),
            Text(
              _packageUploadStage,
            ),
            if (_packageUploadFileName !=
                null) ...[
              const SizedBox(
                height:
                    4,
              ),
              Text(
                _packageUploadFileName!,
                maxLines:
                    1,
                overflow:
                    TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(
              height:
                  10,
            ),
            LinearProgressIndicator(
              value:
                  _packageUploadProgress,
            ),
            const SizedBox(
              height:
                  6,
            ),
            Text(
              '${(_packageUploadProgress * 100).toStringAsFixed(0)}%',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadResultCard(
    TelegramStoragePackageUploadResult result,
  ) {
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
            const Row(
              children: [
                Icon(
                  Icons.cloud_done_outlined,
                ),
                SizedBox(
                  width:
                      10,
                ),
                Text(
                  'Stored in Telegram',
                  style:
                      TextStyle(
                    fontSize:
                        17,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(
              height:
                  10,
            ),
            Wrap(
              spacing:
                  18,
              runSpacing:
                  8,
              children: [
                Text(
                  'Gallery: ${result.galleryMessageIds.length}',
                ),
                Text(
                  'Parts: ${result.partMessageIds.length}',
                ),
                Text(
                  'Uploaded now: ${result.uploadedPartsNow}',
                ),
                Text(
                  'Reused: ${result.reusedParts}',
                ),
                Text(
                  'Manifest: ${result.manifestMessageId}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          14,
        ),
        child:
            Row(
          children: [
            const Icon(
              Icons.info_outline,
            ),
            const SizedBox(
              width:
                  10,
            ),
            Expanded(
              child:
                  Text(
                _status!,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          14,
        ),
        child:
            Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color:
                  Theme.of(context)
                      .colorScheme
                      .error,
            ),
            const SizedBox(
              width:
                  10,
            ),
            Expanded(
              child:
                  Text(
                _error!,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSize(
    int bytes,
  ) {
    const kb =
        1024;

    const mb =
        kb *
        1024;

    const gb =
        mb *
        1024;

    if (bytes >=
        gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }

    if (bytes >=
        mb) {
      return '${(bytes / mb).toStringAsFixed(2)} MB';
    }

    if (bytes >=
        kb) {
      return '${(bytes / kb).toStringAsFixed(1)} KB';
    }

    return '$bytes B';
  }
}

class _CatalogUploadItem {
  final CatalogModel model;

  final String studioName;

  const _CatalogUploadItem({
    required this.model,
    required this.studioName,
  });
}
