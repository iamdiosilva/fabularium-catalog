import 'package:flutter/material.dart';

import '../models/telegram_group.dart';
import '../services/telegram_service.dart';
import 'telegram_messages_page.dart';

class TelegramGroupsPage
    extends StatefulWidget {
  const TelegramGroupsPage({
    super.key,
  });

  @override
  State<TelegramGroupsPage>
      createState() =>
          _TelegramGroupsPageState();
}

class _TelegramGroupsPageState
    extends State<TelegramGroupsPage> {
  final TelegramService _telegram =
      TelegramService.instance;

  bool _isLoading = true;

  String? _error;

  List<TelegramGroup> _groups =
      [];

  String _searchQuery =
      '';

  final TextEditingController
      _searchController =
      TextEditingController();

  @override
  void initState() {
    super.initState();

    _searchController
        .addListener(
      _onSearchChanged,
    );

    _loadGroups();
  }

  @override
  void dispose() {
    _searchController
        .removeListener(
      _onSearchChanged,
    );

    _searchController
        .dispose();

    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery =
          _searchController
              .text
              .trim()
              .toLowerCase();
    });
  }

  Future<void> _loadGroups() async {
    setState(() {
      _isLoading = true;

      _error = null;
    });

    try {
      final groups =
          await _telegram
              .getGroups();

      if (!mounted) {
        return;
      }

      setState(() {
        _groups =
            groups;

        _isLoading =
            false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error =
            e.toString();

        _isLoading =
            false;
      });
    }
  }

  List<TelegramGroup>
      get _filteredGroups {
    if (_searchQuery.isEmpty) {
      return _groups;
    }

    return _groups
        .where(
          (group) =>
              group.title
                  .toLowerCase()
                  .contains(
                    _searchQuery,
                  ),
        )
        .toList();
  }

  Future<void> _openGroup(
    TelegramGroup group,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            TelegramMessagesPage(
          group:
              group,
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Telegram Groups',
        ),
        actions: [
          IconButton(
            tooltip:
                'Refresh',
            onPressed:
                _isLoading
                    ? null
                    : _loadGroups,
            icon:
                const Icon(
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
                'Error loading Telegram groups',
                style:
                    Theme.of(context)
                        .textTheme
                        .titleLarge,
              ),

              const SizedBox(
                height: 12,
              ),

              Text(
                _error!,
                textAlign:
                    TextAlign.center,
              ),

              const SizedBox(
                height: 20,
              ),

              FilledButton.icon(
                onPressed:
                    _loadGroups,
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

    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.fromLTRB(
            24,
            20,
            24,
            12,
          ),
          child: TextField(
            controller:
                _searchController,
            decoration:
                InputDecoration(
              hintText:
                  'Search groups...',
              prefixIcon:
                  const Icon(
                Icons.search,
              ),
              suffixIcon:
                  _searchQuery
                          .isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController
                                .clear();
                          },
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

        Padding(
          padding:
              const EdgeInsets
                  .symmetric(
            horizontal: 24,
          ),
          child: Row(
            children: [
              Text(
                '${_filteredGroups.length} groups',
                style:
                    Theme.of(context)
                        .textTheme
                        .titleMedium,
              ),
            ],
          ),
        ),

        const SizedBox(
          height: 8,
        ),

        Expanded(
          child:
              _filteredGroups.isEmpty
                  ? const Center(
                      child: Text(
                        'No groups found.',
                      ),
                    )
                  : ListView.separated(
                      padding:
                          const EdgeInsets.all(
                        24,
                      ),
                      itemCount:
                          _filteredGroups
                              .length,
                      separatorBuilder:
                          (
                        context,
                        index,
                      ) =>
                              const Divider(
                        height: 1,
                      ),
                      itemBuilder:
                          (
                        context,
                        index,
                      ) {
                        final group =
                            _filteredGroups[
                                index];

                        return ListTile(
                          leading:
                              CircleAvatar(
                            child:
                                Icon(
                              group.isChannel
                                  ? Icons
                                      .groups_2_outlined
                                  : Icons
                                      .group_outlined,
                            ),
                          ),

                          title:
                              Text(
                            group.title,
                          ),

                          subtitle:
                              Text(
                            group.isChannel
                                ? 'Supergroup'
                                : 'Group',
                          ),

                          trailing:
                              const Icon(
                            Icons
                                .chevron_right,
                          ),

                          onTap: () {
                            _openGroup(
                              group,
                            );
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }
}