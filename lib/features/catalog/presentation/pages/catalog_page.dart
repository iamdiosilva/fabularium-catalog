import 'package:flutter/material.dart';

import '../../../../models/catalog_model.dart';
import '../../../../pages/model_detail_page.dart';
import '../../../../pages/pending_models_page.dart';
import '../../../../pages/telegram_login_page.dart';
import '../../application/catalog_controller.dart';
import '../widgets/catalog_model_card.dart';

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
  late final CatalogController _controller;

  final TextEditingController
      _searchController =
      TextEditingController();

  String? _selectedStudio;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();

    _controller = CatalogController(
      fabulariumPath:
          widget.fabulariumPath,
    )
      ..addListener(
        _onControllerChanged,
      )
      ..load();

    _searchController.addListener(
      _onSearchChanged,
    );
  }

  @override
  void dispose() {
    _controller
      ..removeListener(
        _onControllerChanged,
      )
      ..dispose();

    _searchController
      ..removeListener(
        _onSearchChanged,
      )
      ..dispose();

    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }

    if (_selectedStudio != null &&
        !_controller.studios.any(
          (
            studio,
          ) =>
              studio.name ==
              _selectedStudio,
        )) {
      _selectedStudio = null;
    }

    setState(() {});
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery =
          _searchController.text.trim();
    });
  }

  Future<void>
      _openPendingModels() async {
    await Navigator.of(
      context,
    ).push(
      MaterialPageRoute(
        builder: (_) => PendingModelsPage(
          fabulariumPath:
              widget.fabulariumPath,
        ),
      ),
    );

    await _controller.load();
  }

  Future<void> _openModel(
    CatalogModel model,
    String studioName,
  ) async {
    await Navigator.of(
      context,
    ).push(
      MaterialPageRoute(
        builder: (_) => ModelDetailsPage(
          model: model,
          studioName: studioName,
          fabulariumPath:
              widget.fabulariumPath,
        ),
      ),
    );

    await _controller.refreshTelegramStatus(
      model,
    );
  }

  Future<void>
      _refreshTelegramStatuses() async {
    await _controller
        .refreshAllTelegramStatuses();
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
          if (_controller
              .isRefreshingTelegram)
            const Padding(
              padding:
                  EdgeInsets.symmetric(
                horizontal: 8,
              ),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child:
                      CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip:
                'Refresh Telegram Status',
            onPressed:
                _controller.isLoading ||
                        _controller
                            .isRefreshingTelegram
                    ? null
                    : _refreshTelegramStatuses,
            icon: const Icon(
              Icons.cloud_sync_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Telegram',
            onPressed: () {
              Navigator.of(
                context,
              ).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const TelegramLoginPage(),
                ),
              );
            },
            icon: const Icon(
              Icons.telegram,
            ),
          ),
          IconButton(
            tooltip:
                'Register Models',
            onPressed:
                _openPendingModels,
            icon: const Icon(
              Icons.add_box_outlined,
            ),
          ),
          IconButton(
            tooltip:
                'Refresh Catalog',
            onPressed:
                _controller.isLoading
                    ? null
                    : _controller.load,
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
    if (_controller.isLoading) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    if (_controller.error != null) {
      return _buildError();
    }

    if (_controller.studios.isEmpty) {
      return _buildEmpty();
    }

    return Row(
      children: [
        _buildStudioList(),
        Expanded(
          child: Column(
            children: [
              _buildSearchBar(),
              Expanded(
                child:
                    _searchQuery.isNotEmpty
                        ? _buildSearchContent()
                        : _buildStudioContent(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        24,
        20,
        24,
        8,
      ),
      child: TextField(
        controller:
            _searchController,
        decoration: InputDecoration(
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

  Widget _buildStudioList() {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color:
                Theme.of(
              context,
            ).dividerColor,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding:
                const EdgeInsets.all(
              16,
            ),
            child: Text(
              'Studios',
              style:
                  Theme.of(
                context,
              )
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                        fontWeight:
                            FontWeight.bold,
                      ),
            ),
          ),
          const Divider(
            height: 1,
          ),
          Expanded(
            child:
                ListView.builder(
              itemCount:
                  _controller
                      .studios
                      .length,
              itemBuilder:
                  (
                context,
                index,
              ) {
                final studio =
                    _controller
                        .studios[index];

                return ListTile(
                  selected:
                      _selectedStudio ==
                          studio.name,
                  leading:
                      const Icon(
                    Icons
                        .business_outlined,
                  ),
                  title: Text(
                    studio.name,
                    maxLines: 1,
                    overflow:
                        TextOverflow
                            .ellipsis,
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

  Widget _buildSearchContent() {
    final query =
        _normalizeText(
      _searchQuery,
    );

    final results =
        <(CatalogModel, String)>[];

    for (final studio
        in _controller.studios) {
      for (final model
          in studio.models) {
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

        if (_normalizeText(
          searchable,
        ).contains(
          query,
        )) {
          results.add(
            (
              model,
              studio.name,
            ),
          );
        }
      }
    }

    results.sort(
      (
        a,
        b,
      ) =>
          a.$1.name
              .toLowerCase()
              .compareTo(
                b.$1.name
                    .toLowerCase(),
              ),
    );

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            const Icon(
              Icons
                  .search_off_outlined,
              size: 72,
            ),
            const SizedBox(
              height: 16,
            ),
            Text(
              'No models found for "$_searchQuery".',
            ),
            const SizedBox(
              height: 16,
            ),
            OutlinedButton.icon(
              onPressed:
                  _searchController.clear,
              icon: const Icon(
                Icons.clear,
              ),
              label: const Text(
                'Clear Search',
              ),
            ),
          ],
        ),
      );
    }

    return _buildGrid(
      title:
          'Search Results',
      models:
          results,
      showStudio:
          true,
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
            SizedBox(
              height: 16,
            ),
            Text(
              'Select a studio or search for a model',
            ),
          ],
        ),
      );
    }

    final studio =
        _controller.studios.firstWhere(
      (
        studio,
      ) =>
          studio.name ==
          _selectedStudio,
    );

    return _buildGrid(
      title:
          studio.name,
      models:
          studio.models
              .map(
                (
                  model,
                ) =>
                    (
                  model,
                  studio.name,
                ),
              )
              .toList(),
      showStudio:
          false,
    );
  }

  Widget _buildGrid({
    required String title,
    required List<
            (
              CatalogModel,
              String,
            )>
        models,
    required bool showStudio,
  }) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.fromLTRB(
            24,
            16,
            24,
            8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style:
                      Theme.of(
                    context,
                  )
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                            fontWeight:
                                FontWeight.bold,
                          ),
                ),
              ),
              if (_controller
                  .isRefreshingTelegram) ...[
                const Icon(
                  Icons
                      .cloud_sync_outlined,
                  size: 18,
                ),
                const SizedBox(
                  width: 6,
                ),
                Text(
                  'Checking Telegram · ',
                  style:
                      Theme.of(
                    context,
                  )
                          .textTheme
                          .bodySmall,
                ),
              ],
              Text(
                '${models.length} models',
              ),
            ],
          ),
        ),
        Expanded(
          child:
              GridView.builder(
            padding:
                const EdgeInsets.all(
              24,
            ),
            gridDelegate:
                const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent:
                  300,
              childAspectRatio:
                  0.68,
              crossAxisSpacing:
                  20,
              mainAxisSpacing:
                  20,
            ),
            itemCount:
                models.length,
            itemBuilder:
                (
              context,
              index,
            ) {
              final item =
                  models[index];

              return CatalogModelCard(
                model:
                    item.$1,
                studioName:
                    item.$2,
                showStudio:
                    showStudio,
                telegramStatus:
                    _controller
                        .telegramStatusFor(
                  item.$1,
                ),
                onTap: () =>
                    _openModel(
                  item.$1,
                  item.$2,
                ),
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
              Icons
                  .add_box_outlined,
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
            const EdgeInsets.all(
          24,
        ),
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
              style:
                  Theme.of(
                context,
              )
                      .textTheme
                      .titleLarge,
            ),
            const SizedBox(
              height: 12,
            ),
            Text(
              _controller.error ??
                  '',
              textAlign:
                  TextAlign.center,
            ),
            const SizedBox(
              height: 20,
            ),
            FilledButton.icon(
              onPressed:
                  _controller.load,
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
        value.toLowerCase().trim();

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
}
