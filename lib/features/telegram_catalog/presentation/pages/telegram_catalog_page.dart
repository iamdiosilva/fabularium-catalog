import 'package:flutter/material.dart';

import '../../application/telegram_catalog_controller.dart';
import '../../domain/entities/telegram_catalog_entry.dart';
import '../widgets/telegram_catalog_card.dart';
import 'telegram_catalog_detail_page.dart';

class TelegramCatalogPage
    extends StatefulWidget {
  const TelegramCatalogPage({
    super.key,
  });

  @override
  State<TelegramCatalogPage>
      createState() =>
          _TelegramCatalogPageState();
}

class _TelegramCatalogPageState
    extends State<TelegramCatalogPage> {
  late final TelegramCatalogController
      _controller;

  final TextEditingController
      _searchController =
      TextEditingController();

  String _query = '';
  String? _selectedStudio;

  @override
  void initState() {
    super.initState();

    _controller =
        TelegramCatalogController();

    _controller.addListener(
      _onChanged,
    );

    _searchController.addListener(
      _onSearchChanged,
    );

    _controller.load();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(
        _onChanged,
      )
      ..dispose();

    _searchController
      ..removeListener(
        _onSearchChanged,
      )
      ..dispose();

    super.dispose();
  }

  void _onChanged() {
    if (!mounted) {
      return;
    }

    final studios = _studios;

    if (_selectedStudio != null &&
        !studios.contains(
          _selectedStudio,
        )) {
      _selectedStudio = null;
    }

    setState(() {});
  }

  void _onSearchChanged() {
    setState(() {
      _query =
          _normalize(
        _searchController.text,
      );
    });
  }

  List<String> get _studios {
    final result =
        _controller.entries
            .map(
              (entry) =>
                  entry.studio.trim(),
            )
            .where(
              (value) =>
                  value.isNotEmpty,
            )
            .toSet()
            .toList()
          ..sort(
            (
              a,
              b,
            ) =>
                a
                    .toLowerCase()
                    .compareTo(
                      b.toLowerCase(),
                    ),
          );

    return result;
  }

  List<TelegramCatalogEntry>
      get _filteredEntries {
    return _controller.entries.where(
      (
        entry,
      ) {
        if (_selectedStudio != null &&
            entry.studio !=
                _selectedStudio) {
          return false;
        }

        if (_query.isEmpty) {
          return true;
        }

        return _normalize(
          entry.searchText,
        ).contains(
          _query,
        );
      },
    ).toList();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text(
          'Telegram Catalog',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed:
                _controller.isLoading
                    ? null
                    : _controller.load,
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
    if (_controller.isLoading) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    if (_controller.error != null &&
        _controller.entries.isEmpty) {
      return _buildError();
    }

    return Column(
      children: [
        _buildHeader(),
        if (_controller.error != null)
          Padding(
            padding:
                const EdgeInsets.fromLTRB(
              24,
              0,
              24,
              12,
            ),
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  12,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons
                          .error_outline,
                      color:
                          Theme.of(
                        context,
                      )
                              .colorScheme
                              .error,
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    Expanded(
                      child: Text(
                        _controller
                            .error!,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child:
              _buildCatalog(),
        ),
        if (_controller.hasMore)
          _buildLoadMore(),
      ],
    );
  }

  Widget _buildHeader() {
    final studios = _studios;

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        24,
        20,
        24,
        16,
      ),
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child:
                    Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      _controller
                              .channelTitle
                              .isEmpty
                          ? 'Catalog Channel'
                          : _controller
                              .channelTitle,
                      style:
                          Theme.of(
                        context,
                      )
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight:
                                    FontWeight
                                        .bold,
                              ),
                    ),
                    const SizedBox(
                      height: 4,
                    ),
                    const Text(
                      'Models loaded directly from Telegram.',
                    ),
                  ],
                ),
              ),
              Chip(
                avatar:
                    const Icon(
                  Icons
                      .cloud_outlined,
                  size: 18,
                ),
                label:
                    Text(
                  '${_controller.entries.length} loaded',
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 16,
          ),
          Row(
            children: [
              Expanded(
                child:
                    TextField(
                  controller:
                      _searchController,
                  decoration:
                      InputDecoration(
                    hintText:
                        'Search Telegram catalog...',
                    prefixIcon:
                        const Icon(
                      Icons.search,
                    ),
                    suffixIcon:
                        _searchController
                                .text
                                .isNotEmpty
                            ? IconButton(
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
              ),
              const SizedBox(
                width: 12,
              ),
              SizedBox(
                width: 230,
                child:
                    DropdownButtonFormField<
                        String?>(
                  initialValue:
                      _selectedStudio,
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Studio',
                    border:
                        OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<
                        String?>(
                      value: null,
                      child: Text(
                        'All Studios',
                      ),
                    ),
                    ...studios.map(
                      (
                        studio,
                      ) =>
                          DropdownMenuItem<
                              String?>(
                        value: studio,
                        child: Text(
                          studio,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged:
                      (
                    value,
                  ) {
                    setState(() {
                      _selectedStudio =
                          value;
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCatalog() {
    final entries =
        _filteredEntries;

    if (entries.isEmpty) {
      return Center(
        child:
            Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            const Icon(
              Icons
                  .cloud_off_outlined,
              size: 72,
            ),
            const SizedBox(
              height: 14,
            ),
            Text(
              _controller.entries.isEmpty
                  ? 'No Fabularium catalog posts were found in Telegram.'
                  : 'No models match the current filters.',
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding:
          const EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24,
      ),
      gridDelegate:
          const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 310,
        childAspectRatio: 0.72,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount:
          entries.length,
      itemBuilder:
          (
        context,
        index,
      ) {
        final entry =
            entries[index];

        return TelegramCatalogCard(
          entry: entry,
          onTap: () {
            Navigator.of(
              context,
            ).push(
              MaterialPageRoute(
                builder:
                    (_) =>
                        TelegramCatalogDetailPage(
                  entry: entry,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLoadMore() {
    return SafeArea(
      top: false,
      child:
          Padding(
        padding:
            const EdgeInsets.fromLTRB(
          24,
          0,
          24,
          18,
        ),
        child:
            SizedBox(
          width:
              double.infinity,
          child:
              FilledButton.tonalIcon(
            onPressed:
                _controller
                        .isLoadingMore
                    ? null
                    : _controller
                        .loadMore,
            icon:
                _controller
                        .isLoadingMore
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
                            .expand_more,
                      ),
            label:
                Text(
              _controller
                      .isLoadingMore
                  ? 'Loading older models...'
                  : 'Load Older Models',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          24,
        ),
        child:
            Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            const Icon(
              Icons
                  .cloud_off_outlined,
              size: 72,
            ),
            const SizedBox(
              height: 16,
            ),
            Text(
              'Could not load Telegram Catalog',
              style:
                  Theme.of(
                context,
              )
                      .textTheme
                      .titleLarge,
            ),
            const SizedBox(
              height: 10,
            ),
            Text(
              _controller.error ??
                  '',
              textAlign:
                  TextAlign.center,
            ),
            const SizedBox(
              height: 18,
            ),
            FilledButton.icon(
              onPressed:
                  _controller.load,
              icon:
                  const Icon(
                Icons.refresh,
              ),
              label:
                  const Text(
                'Try Again',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _normalize(
    String value,
  ) {
    const replacements =
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

    replacements.forEach(
      (
        source,
        target,
      ) {
        result =
            result.replaceAll(
          source,
          target,
        );
      },
    );

    return result;
  }
}
