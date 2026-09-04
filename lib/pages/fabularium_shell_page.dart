import 'dart:async';

import 'package:flutter/material.dart';

import '../features/catalog/presentation/pages/catalog_page.dart';
import '../features/community/application/community_auth_service.dart';
import '../features/community/presentation/pages/community_account_page.dart';
import '../features/community/presentation/pages/community_catalog_page.dart';
import '../features/community/presentation/pages/community_moderation_page.dart';
import '../features/community/presentation/pages/community_my_submissions_page.dart';
import '../features/community/presentation/pages/community_new_submission_page.dart';
import '../services/community_storage_endpoint_sync_service.dart';
import '../services/download_queue_service.dart';
import '../services/telegram_service.dart';
import 'download_access_page.dart';
import 'download_queue_page.dart';
import 'telegram_catalog_page.dart';
import 'telegram_login_page.dart';
import 'telegram_storage_settings_page.dart';

class FabulariumShellPage extends StatefulWidget {
  final String fabulariumPath;

  const FabulariumShellPage({
    super.key,
    required this.fabulariumPath,
  });

  @override
  State<FabulariumShellPage> createState() => _FabulariumShellPageState();
}

enum _FabulariumSection {
  explore,
  contribute,
  downloads,
  account,
  studio,
}

class _FabulariumShellPageState extends State<FabulariumShellPage> {
  final CommunityAuthService _auth = CommunityAuthService.instance;

  _FabulariumSection _section = _FabulariumSection.explore;
  bool _syncingStorage = false;
  bool _storageSynced = false;
  String? _storageSyncError;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncStorageRouting();
    });
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;

    if (!_auth.isAdmin && _section == _FabulariumSection.studio) {
      _section = _FabulariumSection.explore;
    }

    setState(() {});

    if (_auth.isAdmin && !_storageSynced && !_syncingStorage) {
      unawaited(_syncStorageRouting());
    }
  }

  Future<void> _syncStorageRouting() async {
    if (!_auth.isAdmin || _syncingStorage) return;

    setState(() {
      _syncingStorage = true;
      _storageSyncError = null;
    });

    try {
      await CommunityStorageEndpointSyncService.instance.syncIfAdmin();

      if (mounted) {
        setState(() {
          _storageSynced = true;
          _storageSyncError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _storageSynced = false;
          _storageSyncError = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncingStorage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final extended = constraints.maxWidth >= 1180;

        final sections = <_FabulariumSection>[
          _FabulariumSection.explore,
          _FabulariumSection.contribute,
          _FabulariumSection.downloads,
          _FabulariumSection.account,
          if (_auth.isAdmin) _FabulariumSection.studio,
        ];

        if (!sections.contains(_section)) {
          _section = _FabulariumSection.explore;
        }

        final selectedIndex = sections.indexOf(_section);

        return Scaffold(
          body: Row(
            children: <Widget>[
              NavigationRail(
                extended: extended,
                selectedIndex: selectedIndex,
                onDestinationSelected: (index) {
                  setState(() {
                    _section = sections[index];
                  });
                },
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: extended
                      ? const Text(
                          'FABULARIUM',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        )
                      : const Icon(Icons.auto_awesome),
                ),
                destinations: sections.map(_destinationFor).toList(),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _buildSection()),
            ],
          ),
        );
      },
    );
  }

  NavigationRailDestination _destinationFor(_FabulariumSection section) {
    switch (section) {
      case _FabulariumSection.explore:
        return const NavigationRailDestination(
          icon: Icon(Icons.explore_outlined),
          selectedIcon: Icon(Icons.explore),
          label: Text('Explore'),
        );
      case _FabulariumSection.contribute:
        return const NavigationRailDestination(
          icon: Icon(Icons.upload_file_outlined),
          selectedIcon: Icon(Icons.upload_file),
          label: Text('Contribute'),
        );
      case _FabulariumSection.downloads:
        return const NavigationRailDestination(
          icon: Icon(Icons.download_outlined),
          selectedIcon: Icon(Icons.download),
          label: Text('Downloads'),
        );
      case _FabulariumSection.account:
        return NavigationRailDestination(
          icon: Icon(
            _auth.isSignedIn
                ? Icons.account_circle_outlined
                : Icons.person_outline,
          ),
          selectedIcon: Icon(
            _auth.isSignedIn ? Icons.account_circle : Icons.person,
          ),
          label: const Text('Account'),
        );
      case _FabulariumSection.studio:
        return const NavigationRailDestination(
          icon: Icon(Icons.build_outlined),
          selectedIcon: Icon(Icons.build),
          label: Text('Studio Tools'),
        );
    }
  }

  Widget _buildSection() {
    switch (_section) {
      case _FabulariumSection.explore:
        return const CommunityCatalogPage(embedded: true);
      case _FabulariumSection.contribute:
        return _ContributeSection(
          signedIn: _auth.isSignedIn,
          onSignIn: _openAccount,
          onSubmissions: _openMySubmissions,
          onNewSubmission: _openNewSubmission,
        );
      case _FabulariumSection.downloads:
        return _DownloadsSection(
          onOpenQueue: _openDownloads,
          onDownloadAccess: _openDownloadAccess,
        );
      case _FabulariumSection.account:
        return _AccountSection(
          auth: _auth,
          onAccount: _openAccount,
          onDownloadAccess: _openDownloadAccess,
        );
      case _FabulariumSection.studio:
        return _StudioToolsSection(
          fabulariumPath: widget.fabulariumPath,
          syncingStorage: _syncingStorage,
          storageSynced: _storageSynced,
          storageSyncError: _storageSyncError,
          onSyncStorage: _syncStorageRouting,
        );
    }
  }

  Future<void> _openAccount() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CommunityAccountPage()),
    );

    await _auth.refresh();
    if (mounted) setState(() {});
  }

  void _openDownloads() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DownloadQueuePage()),
    );
  }

  Future<void> _openDownloadAccess() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DownloadAccessPage()),
    );

    if (mounted) setState(() {});
  }

  void _openMySubmissions() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CommunityMySubmissionsPage()),
    );
  }

  void _openNewSubmission() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CommunityNewSubmissionPage()),
    );
  }
}

class _ContributeSection extends StatelessWidget {
  final bool signedIn;
  final VoidCallback onSignIn;
  final VoidCallback onSubmissions;
  final VoidCallback onNewSubmission;

  const _ContributeSection({
    required this.signedIn,
    required this.onSignIn,
    required this.onSubmissions,
    required this.onNewSubmission,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionLayout(
      title: 'Contribute',
      subtitle:
          'Share models with the community. Fabularium handles validation, storage and moderation.',
      children: <Widget>[
        _ActionCard(
          icon: Icons.upload_file_outlined,
          title: signedIn ? 'Submit a model' : 'Sign in to contribute',
          description: signedIn
              ? 'Choose an archive, add metadata and send it for moderation.'
              : 'A Fabularium account is required for submissions, reputation and publishing history.',
          actionLabel: signedIn ? 'New Submission' : 'Sign In',
          onPressed: signedIn ? onNewSubmission : onSignIn,
        ),
        if (signedIn)
          _ActionCard(
            icon: Icons.inventory_2_outlined,
            title: 'My submissions',
            description:
                'Track uploads, processing, moderation and publication status.',
            actionLabel: 'Open Submissions',
            onPressed: onSubmissions,
          ),
      ],
    );
  }
}

class _DownloadsSection extends StatelessWidget {
  final VoidCallback onOpenQueue;
  final VoidCallback onDownloadAccess;

  const _DownloadsSection({
    required this.onOpenQueue,
    required this.onDownloadAccess,
  });

  @override
  Widget build(BuildContext context) {
    final queue = DownloadQueueService.instance;

    return AnimatedBuilder(
      animation: queue,
      builder: (context, _) {
        return _SectionLayout(
          title: 'Downloads',
          subtitle:
              'Large files transfer directly to your computer through Fabularium.',
          children: <Widget>[
            _ActionCard(
              icon: Icons.download_for_offline_outlined,
              title: 'Download queue',
              description:
                  '${queue.activeCount} active · ${queue.completedCount} completed · ${queue.failedCount} failed',
              actionLabel: 'Open Downloads',
              onPressed: onOpenQueue,
            ),
            _ActionCard(
              icon: TelegramService.instance.hasSavedSession
                  ? Icons.link
                  : Icons.link_off,
              title: 'Download Access',
              description: TelegramService.instance.hasSavedSession
                  ? 'A transfer account is configured on this computer.'
                  : 'Connect once before your first community download.',
              actionLabel: 'Manage Connection',
              onPressed: onDownloadAccess,
            ),
          ],
        );
      },
    );
  }
}

class _AccountSection extends StatelessWidget {
  final CommunityAuthService auth;
  final VoidCallback onAccount;
  final VoidCallback onDownloadAccess;

  const _AccountSection({
    required this.auth,
    required this.onAccount,
    required this.onDownloadAccess,
  });

  @override
  Widget build(BuildContext context) {
    final profile = auth.profile;

    return _SectionLayout(
      title: 'Account',
      subtitle: auth.isSignedIn
          ? 'Signed in as ${profile?.displayName ?? auth.email ?? 'Fabularium user'}'
          : 'Sign in to like models, contribute and download.',
      children: <Widget>[
        _ActionCard(
          icon: auth.isSignedIn ? Icons.account_circle_outlined : Icons.login,
          title: auth.isSignedIn && profile?.username != null
              ? '@${profile!.username}'
              : 'Fabularium Account',
          description: auth.isSignedIn
              ? 'Points: ${profile?.points ?? 0} · Reputation: ${profile?.reputation ?? 0} · ${auth.isAdmin ? 'ADMIN' : 'USER'}'
              : 'Your community identity, submissions, likes and reputation.',
          actionLabel:
              auth.isSignedIn ? 'Manage Account' : 'Sign In / Create Account',
          onPressed: onAccount,
        ),
        _ActionCard(
          icon: TelegramService.instance.hasSavedSession
              ? Icons.cloud_done_outlined
              : Icons.cloud_download_outlined,
          title: 'Download Access',
          description: TelegramService.instance.hasSavedSession
              ? 'Ready for direct community downloads.'
              : 'Connect your transfer account when you are ready to download.',
          actionLabel: 'Manage',
          onPressed: onDownloadAccess,
        ),
      ],
    );
  }
}

class _StudioToolsSection extends StatelessWidget {
  final String fabulariumPath;
  final bool syncingStorage;
  final bool storageSynced;
  final String? storageSyncError;
  final Future<void> Function() onSyncStorage;

  const _StudioToolsSection({
    required this.fabulariumPath,
    required this.syncingStorage,
    required this.storageSynced,
    required this.storageSyncError,
    required this.onSyncStorage,
  });

  @override
  Widget build(BuildContext context) {
    void open(Widget page) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => page),
      );
    }

    return _SectionLayout(
      title: 'Studio Tools',
      subtitle:
          'Administrative and legacy tools are kept here, away from the normal community flow.',
      children: <Widget>[
        _ActionCard(
          icon: Icons.collections_bookmark_outlined,
          title: 'Local Studio Library',
          description:
              'Your original file-system catalog and direct Official Storage workflow.',
          actionLabel: 'Open Local Catalog',
          onPressed: () => open(
            CatalogPage(fabulariumPath: fabulariumPath),
          ),
        ),
        _ActionCard(
          icon: Icons.fact_check_outlined,
          title: 'Community Moderation',
          description: 'Approve, reject and inspect submitted models.',
          actionLabel: 'Open Moderation',
          onPressed: () => open(const CommunityModerationPage()),
        ),
        _ActionCard(
          icon: storageSynced ? Icons.sync_alt : Icons.sync_problem_outlined,
          title: 'Community Download Routing',
          description: syncingStorage
              ? 'Synchronizing public Official endpoints...'
              : storageSynced
                  ? 'Official Catalog/Files routing is synchronized for community downloads.'
                  : storageSyncError ??
                      'Synchronize the public Official channel usernames with Supabase.',
          actionLabel: syncingStorage ? 'Syncing...' : 'Sync Routing',
          onPressed: syncingStorage ? null : () => onSyncStorage(),
        ),
        _ActionCard(
          icon: Icons.settings_suggest_outlined,
          title: 'Telegram Storage Workspace',
          description:
              'Configure Official Catalog, Official Files and private Pending.',
          actionLabel: 'Storage Settings',
          onPressed: () => open(const TelegramStorageSettingsPage()),
        ),
        _ActionCard(
          icon: Icons.history_outlined,
          title: 'Legacy Telegram Tools',
          description:
              'Low-level Telegram login, groups and the previous Telegram Catalog remain available for administration.',
          actionLabel: 'Open Telegram Tools',
          onPressed: () => open(const TelegramLoginPage()),
          secondaryLabel: 'Legacy Catalog',
          onSecondary: () => open(const TelegramCatalogPage()),
        ),
      ],
    );
  }
}

class _SectionLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _SectionLayout({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 28),
        Wrap(
          spacing: 18,
          runSpacing: 18,
          children: children,
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback? onPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onPressed,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 410,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 34),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(description),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonal(
                    onPressed: onPressed,
                    child: Text(actionLabel),
                  ),
                  if (secondaryLabel != null && onSecondary != null)
                    TextButton(
                      onPressed: onSecondary,
                      child: Text(secondaryLabel!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
