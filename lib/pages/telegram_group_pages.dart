import 'package:flutter/material.dart';

import '../models/telegram_group.dart';
import '../services/telegram_groups_worker.dart';
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
  final TelegramGroupsWorker
      _groupsWorker =
      TelegramGroupsWorker.instance;

  bool _isLoading =
      true;

  bool _isRefreshing =
      false;

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

    _searchController.addListener(
      _onSearchChanged,
    );

    _loadGroups();
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
              .trim()
              .toLowerCase();
    });
  }

  Future<void> _loadGroups({
    bool forceRefresh = false,
  }) async {
    if (_isRefreshing) {
      return;
    }

    if (forceRefresh) {
      setState(() {
        _isRefreshing =
            true;

        _error =
            null;
      });
    } else {
      setState(() {
        _isLoading =
            true;

        _error =
            null;
      });
    }

    try {
      /*
       * Primeira chamada:
       *
       * Telegram em isolate separado.
       *
       * Próximas chamadas:
       *
       * cache instantâneo.
       */
      final groups =
          await _groupsWorker
              .getGroups(
        forceRefresh:
            forceRefresh,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _groups =
            groups;

        _isLoading =
            false;

        _isRefreshing =
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

        _isRefreshing =
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
        builder:
            (_) =>
                TelegramMessagesPage(
          group:
              group,
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    await _loadGroups(
      forceRefresh:
          true,
    );
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
          'Telegram Groups',
        ),
        actions: [
          if (_isRefreshing)
            const Padding(
              padding:
                  EdgeInsets.symmetric(
                horizontal:
                    18,
              ),
              child:
                  Center(
                child:
                    SizedBox(
                  width:
                      18,
                  height:
                      18,
                  child:
                      CircularProgressIndicator(
                    strokeWidth:
                        2,
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip:
                  'Refresh',
              onPressed:
                  _isLoading
                      ? null
                      : _refresh,
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
    /*
     * Loading somente quando ainda
     * não existe nenhuma lista.
     */
    if (_isLoading &&
        _groups.isEmpty) {
      return const Center(
        child:
            Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            CircularProgressIndicator(),

            SizedBox(
              height:
                  16,
            ),

            Text(
              'Loading Telegram groups...',
            ),
          ],
        ),
      );
    }

    if (_error != null &&
        _groups.isEmpty) {
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
                Icons.error_outline,
                size:
                    64,
              ),

              const SizedBox(
                height:
                    16,
              ),

              Text(
                'Error loading Telegram groups',
                style:
                    Theme.of(context)
                        .textTheme
                        .titleLarge,
              ),

              const SizedBox(
                height:
                    12,
              ),

              Text(
                _error!,
                textAlign:
                    TextAlign.center,
              ),

              const SizedBox(
                height:
                    20,
              ),

              FilledButton.icon(
                onPressed:
                    () {
                  _loadGroups(
                    forceRefresh:
                        true,
                  );
                },
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

    final filteredGroups =
        _filteredGroups;

    return Column(
      children: [
        if (_isRefreshing)
          const LinearProgressIndicator(
            minHeight:
                2,
          ),

        Padding(
          padding:
              const EdgeInsets.fromLTRB(
            24,
            20,
            24,
            12,
          ),
          child:
              TextField(
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
                  _searchQuery.isNotEmpty
                      ? IconButton(
                          tooltip:
                              'Clear Search',
                          onPressed:
                              _searchController
                                  .clear,
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
              const EdgeInsets.symmetric(
            horizontal:
                24,
          ),
          child:
              Row(
            children: [
              Text(
                '${filteredGroups.length} groups',
                style:
                    Theme.of(context)
                        .textTheme
                        .titleMedium,
              ),

              const Spacer(),

              if (_isRefreshing)
                Text(
                  'Updating...',
                  style:
                      Theme.of(context)
                          .textTheme
                          .bodySmall,
                ),
            ],
          ),
        ),

        const SizedBox(
          height:
              8,
        ),

        Expanded(
          child:
              filteredGroups.isEmpty
                  ? const Center(
                      child:
                          Text(
                        'No groups found.',
                      ),
                    )
                  : ListView.separated(
                      padding:
                          const EdgeInsets.all(
                        24,
                      ),
                      itemCount:
                          filteredGroups.length,
                      separatorBuilder:
                          (
                        context,
                        index,
                      ) =>
                              const Divider(
                        height:
                            1,
                      ),
                      itemBuilder:
                          (
                        context,
                        index,
                      ) {
                        final group =
                            filteredGroups[
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

                          onTap:
                              () {
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