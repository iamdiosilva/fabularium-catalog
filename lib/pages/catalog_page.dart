import 'package:flutter/material.dart';

import '../models/catalog_model.dart';
import '../services/cagalog_scanner.dart';
import 'model_detail_page.dart';
import 'pending_models_page.dart';

class CatalogPage extends StatefulWidget {
  final String fabulariumPath;

  const CatalogPage({
    super.key,
    required this.fabulariumPath,
  });

  @override
  State<CatalogPage> createState() =>
      _CatalogPageState();
}

class _CatalogPageState
    extends State<CatalogPage> {
  final CatalogScanner _scanner =
      CatalogScanner();

  bool _isLoading = true;

  String? _error;

  List<CatalogStudio> _studios = [];

  String? _selectedStudio;

  @override
  void initState() {
    super.initState();

    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final studios =
          await _scanner.scan(
        widget.fabulariumPath,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _studios = studios;

        if (_selectedStudio != null &&
            !_studios.any(
              (studio) =>
                  studio.name ==
                  _selectedStudio,
            )) {
          _selectedStudio = null;
        }

        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _openPendingModels() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PendingModelsPage(
          fabulariumPath:
              widget.fabulariumPath,
        ),
      ),
    );

    await _loadCatalog();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Fabularium Catalog',
        ),
        actions: [
          IconButton(
            tooltip: 'Register Models',
            onPressed:
                _openPendingModels,
            icon: const Icon(
              Icons.add_box_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Refresh Catalog',
            onPressed: _isLoading
                ? null
                : _loadCatalog,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return _buildError();
    }

    if (_studios.isEmpty) {
      return _buildEmpty();
    }

    return Row(
      children: [
        _buildStudioList(),
        Expanded(
          child:
              _buildStudioContent(),
        ),
      ],
    );
  }

  Widget _buildStudioList() {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: Theme.of(context)
                .dividerColor,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding:
                const EdgeInsets.all(16),
            child: Text(
              'Studios',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(
                    fontWeight:
                        FontWeight.bold,
                  ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount:
                  _studios.length,
              itemBuilder:
                  (context, index) {
                final studio =
                    _studios[index];

                final selected =
                    _selectedStudio ==
                        studio.name;

                return ListTile(
                  selected: selected,
                  leading: const Icon(
                    Icons
                        .business_outlined,
                  ),
                  title: Text(
                    studio.name,
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    '${studio.models.length}',
                  ),
                  onTap: () {
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

  Widget _buildStudioContent() {
    if (_selectedStudio == null) {
      return const Center(
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Icon(
              Icons
                  .collections_bookmark_outlined,
              size: 72,
            ),
            SizedBox(height: 16),
            Text(
              'Select a studio',
            ),
          ],
        ),
      );
    }

    final studio =
        _studios.firstWhere(
      (studio) =>
          studio.name ==
          _selectedStudio,
    );

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.fromLTRB(
            24,
            24,
            24,
            8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  studio.name,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(
                        fontWeight:
                            FontWeight.bold,
                      ),
                ),
              ),
              Text(
                '${studio.models.length} models',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding:
                const EdgeInsets.all(24),
            gridDelegate:
                const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 300,
              childAspectRatio: 0.72,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
            ),
            itemCount:
                studio.models.length,
            itemBuilder:
                (context, index) {
              final model =
                  studio.models[index];

              return ModelCard(
                model: model,
                studioName:
                    studio.name,
                fabulariumPath:
                    widget.fabulariumPath,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          const Icon(
            Icons
                .inventory_2_outlined,
            size: 72,
          ),
          const SizedBox(
            height: 16,
          ),
          const Text(
            'No models found.',
          ),
          const SizedBox(
            height: 20,
          ),
          FilledButton.icon(
            onPressed:
                _openPendingModels,
            icon: const Icon(
              Icons.add_box_outlined,
            ),
            label: const Text(
              'Register Models',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(24),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
            ),
            const SizedBox(
              height: 16,
            ),
            Text(
              'Error Loading Catalog',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge,
            ),
            const SizedBox(
              height: 12,
            ),
            Text(
              _error ?? '',
              textAlign:
                  TextAlign.center,
            ),
            const SizedBox(
              height: 20,
            ),
            FilledButton.icon(
              onPressed:
                  _loadCatalog,
              icon: const Icon(
                Icons.refresh,
              ),
              label: const Text(
                'Try Again',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ModelCard extends StatelessWidget {
  final CatalogModel model;

  final String studioName;

  final String fabulariumPath;

  const ModelCard({
    super.key,
    required this.model,
    required this.studioName,
    required this.fabulariumPath,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final preview =
        model.images.isNotEmpty
            ? model.images.first
            : null;

    return Card(
      clipBehavior:
          Clip.antiAlias,
      elevation: 3,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context)
              .push(
            MaterialPageRoute(
              builder: (_) =>
                  ModelDetailsPage(
                model: model,
                studioName:
                    studioName,
                fabulariumPath:
                    fabulariumPath,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: preview != null
                  ? Image.file(
                      preview,
                      fit: BoxFit.cover,
                      cacheWidth: 600,
                      errorBuilder: (
                        context,
                        error,
                        stackTrace,
                      ) {
                        return const Center(
                          child: Icon(
                            Icons
                                .broken_image_outlined,
                            size: 48,
                          ),
                        );
                      },
                    )
                  : const Center(
                      child: Icon(
                        Icons
                            .image_outlined,
                        size: 48,
                      ),
                    ),
            ),
            Padding(
              padding:
                  const EdgeInsets.all(
                12,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    model.name,
                    maxLines: 2,
                    overflow: TextOverflow
                        .ellipsis,
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(
                    height: 6,
                  ),
                  if (model.category
                      .isNotEmpty)
                    Text(
                      model.category,
                      maxLines: 1,
                      overflow:
                          TextOverflow
                              .ellipsis,
                    ),
                  if (model.type
                      .isNotEmpty) ...[
                    const SizedBox(
                      height: 4,
                    ),
                    Text(
                      _getTypeLabel(
                        model.type,
                      ),
                      style: Theme.of(
                        context,
                      )
                          .textTheme
                          .bodySmall,
                    ),
                  ],
                  const SizedBox(
                    height: 8,
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons
                            .photo_library_outlined,
                        size: 16,
                      ),
                      const SizedBox(
                        width: 4,
                      ),
                      Text(
                        '${model.images.length}',
                      ),
                      const SizedBox(
                        width: 12,
                      ),
                      const Icon(
                        Icons
                            .archive_outlined,
                        size: 16,
                      ),
                      const SizedBox(
                        width: 4,
                      ),
                      Text(
                        '${model.archiveFiles.length}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTypeLabel(
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