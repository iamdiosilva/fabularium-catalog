import '../features/community/application/community_auth_service.dart';
import '../features/community/data/community_catalog_repository.dart';
import 'telegram_storage_workspace_service.dart';

class CommunityStorageEndpointSyncService {
  CommunityStorageEndpointSyncService._();

  static final CommunityStorageEndpointSyncService instance =
      CommunityStorageEndpointSyncService._();

  final CommunityCatalogRepository _repository =
      CommunityCatalogRepository.instance;

  final TelegramStorageWorkspaceService _workspace =
      TelegramStorageWorkspaceService.instance;

  Future<void> syncIfAdmin() async {
    final auth = CommunityAuthService.instance;
    if (!auth.isAdmin) return;

    final workspace = await _workspace.load();
    final catalog = workspace.catalogChannel;
    final files = workspace.filesChannel;

    if (catalog == null || files == null) {
      throw const CommunityStorageEndpointSyncException(
        'Catalog and Files Telegram channels are not configured.',
      );
    }

    final catalogUsername = catalog.publicUsername;
    final filesUsername = files.publicUsername;

    if (catalogUsername == null || filesUsername == null) {
      throw const CommunityStorageEndpointSyncException(
        'Catalog and Files must be public before download routing can be synchronized.',
      );
    }

    await _repository.syncStorageEndpoints(
      catalogChannelId: catalog.id,
      catalogUsername: catalogUsername,
      filesChannelId: files.id,
      filesUsername: filesUsername,
    );
  }
}

class CommunityStorageEndpointSyncException implements Exception {
  final String message;

  const CommunityStorageEndpointSyncException(this.message);

  @override
  String toString() => message;
}
