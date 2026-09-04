import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/community_catalog_repository.dart';
import '../../domain/community_catalog_model.dart';
import 'community_catalog_detail_page.dart';

class CommunityCatalogPage extends StatefulWidget {
  final bool embedded;

  const CommunityCatalogPage({
    super.key,
    this.embedded = false,
  });

  @override
  State<CommunityCatalogPage> createState() => _CommunityCatalogPageState();
}

class _CommunityCatalogPageState extends State<CommunityCatalogPage> {
  static const int _pageSize = 24;

  final CommunityCatalogRepository _repository =
      CommunityCatalogRepository.instance;
  final TextEditingController _search = TextEditingController();

  Timer? _debounce;
  CommunityCatalogFilters _filters = const CommunityCatalogFilters.empty();
  final List<CommunityCatalogModel> _items = <CommunityCatalogModel>[];

  String? _selectedCategory;
  String? _selectedStudio;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final filters = await _repository.loadFilters();
      if (mounted) {
        setState(() {
          _filters = filters;
        });
      }
    } catch (_) {}

    await _load(reset: true);
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _load(reset: true),
    );
    if (mounted) setState(() {});
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      if (_loadingMore || _items.length >= _total) return;
      setState(() {
        _loadingMore = true;
      });
    }

    try {
      final result = await _repository.loadCatalog(
        search: _search.text,
        category: _selectedCategory,
        studio: _selectedStudio,
        limit: _pageSize,
        offset: reset ? 0 : _items.length,
      );

      if (!mounted) return;

      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(result.items);
        } else {
          _items.addAll(result.items);
        }
        _total = result.total;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();

    if (widget.embedded) return content;

    return Scaffold(
      appBar: AppBar(title: const Text('Community')),
      body: content,
    );
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildHeader(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Community Catalog',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Discover models published by the Fabularium community.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 820;

              final search = TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Search models, studios, categories or tags...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: _search.clear,
                          icon: const Icon(Icons.clear),
                        ),
                  border: const OutlineInputBorder(),
                ),
              );

              final category = _filterDropdown(
                label: 'Category',
                value: _selectedCategory,
                values: _filters.categories,
                onChanged: (value) {
                  setState(() {
                    _selectedCategory = value;
                  });
                  _load(reset: true);
                },
              );

              final studio = _filterDropdown(
                label: 'Studio',
                value: _selectedStudio,
                values: _filters.studios,
                onChanged: (value) {
                  setState(() {
                    _selectedStudio = value;
                  });
                  _load(reset: true);
                },
              );

              if (compact) {
                return Column(
                  children: <Widget>[
                    search,
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(child: category),
                        const SizedBox(width: 12),
                        Expanded(child: studio),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: <Widget>[
                  Expanded(child: search),
                  const SizedBox(width: 12),
                  SizedBox(width: 190, child: category),
                  const SizedBox(width: 12),
                  SizedBox(width: 190, child: studio),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _filterDropdown({
    required String label,
    required String? value,
    required List<String> values,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: <DropdownMenuItem<String?>>[
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('All'),
        ),
        ...values.map(
          (item) => DropdownMenuItem<String?>(
            value: item,
            child: Text(item, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.cloud_off_outlined, size: 64),
              const SizedBox(height: 14),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: () => _load(reset: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.inventory_2_outlined, size: 72),
            SizedBox(height: 16),
            Text('No published models match these filters.'),
          ],
        ),
      );
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(
            children: <Widget>[
              Text('${_items.length} of $_total models'),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => _load(reset: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 28),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 330,
              childAspectRatio: 0.78,
              crossAxisSpacing: 18,
              mainAxisSpacing: 18,
            ),
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final model = _items[index];

              return _CommunityModelCard(
                model: model,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CommunityCatalogDetailPage(model: model),
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (_items.length < _total)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: FilledButton.tonalIcon(
              onPressed: _loadingMore ? null : () => _load(reset: false),
              icon: _loadingMore
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more),
              label: const Text('Load More'),
            ),
          ),
      ],
    );
  }
}

class _CommunityModelCard extends StatelessWidget {
  final CommunityCatalogModel model;
  final VoidCallback onTap;

  const _CommunityModelCard({
    required this.model,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              flex: 5,
              child: Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.view_in_ar_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      model.category ?? 'Community Model',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      model.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 6),
                    if (model.studio != null)
                      Text(
                        model.studio!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 6),
                    Text(
                      model.contributorLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    Row(
                      children: <Widget>[
                        const Icon(Icons.favorite_border, size: 17),
                        const SizedBox(width: 5),
                        Text('${model.likeCount}'),
                        const Spacer(),
                        Text(
                          _formatBytes(model.archiveSize),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '';

    const mb = 1024 * 1024;
    const gb = mb * 1024;

    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    return '${(bytes / mb).toStringAsFixed(0)} MB';
  }
}
