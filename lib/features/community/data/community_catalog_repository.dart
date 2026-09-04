import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/supabase_service.dart';
import '../domain/community_catalog_model.dart';
import '../domain/community_download_ticket.dart';

class CommunityCatalogRepository {
  CommunityCatalogRepository._();

  static final CommunityCatalogRepository instance =
      CommunityCatalogRepository._();

  SupabaseClient get _client {
    final client = SupabaseService.instance.client;
    if (client == null) {
      throw const CommunityCatalogRepositoryException(
        'Supabase is not initialized.',
      );
    }
    return client;
  }

  Future<CommunityCatalogPageResult> loadCatalog({
    String? search,
    String? category,
    String? studio,
    int limit = 24,
    int offset = 0,
  }) async {
    final raw = await _client.rpc(
      'browse_fabularium_catalog',
      params: <String, dynamic>{
        'search_text': _emptyToNull(search),
        'category_filter': _emptyToNull(category),
        'studio_filter': _emptyToNull(studio),
        'page_limit': limit,
        'page_offset': offset,
      },
    );

    if (raw is! Map) {
      return const CommunityCatalogPageResult(
        items: <CommunityCatalogModel>[],
        total: 0,
      );
    }

    return CommunityCatalogPageResult.fromJson(
      Map<String, dynamic>.from(raw),
    );
  }

  Future<CommunityCatalogFilters> loadFilters() async {
    final raw = await _client.rpc('get_fabularium_catalog_filters');

    if (raw is! Map) {
      return const CommunityCatalogFilters.empty();
    }

    return CommunityCatalogFilters.fromJson(
      Map<String, dynamic>.from(raw),
    );
  }

  Future<CommunityDownloadTicket> loadDownloadTicket(
    String modelId,
  ) async {
    final raw = await _client.rpc(
      'get_fabularium_download_ticket',
      params: <String, dynamic>{
        'target_model_id': modelId,
      },
    );

    if (raw is! Map) {
      throw const CommunityCatalogRepositoryException(
        'Fabularium did not return a download ticket.',
      );
    }

    final ticket = CommunityDownloadTicket.fromJson(
      Map<String, dynamic>.from(raw),
    );

    if (ticket.filesUsername.isEmpty || ticket.parts.isEmpty) {
      throw const CommunityCatalogRepositoryException(
        'This model is not ready for direct download yet.',
      );
    }

    return ticket;
  }

  Future<void> syncStorageEndpoints({
    required int catalogChannelId,
    required String catalogUsername,
    required int filesChannelId,
    required String filesUsername,
  }) async {
    await _client.rpc(
      'admin_sync_fabularium_storage_endpoints',
      params: <String, dynamic>{
        'catalog_channel_id': catalogChannelId,
        'catalog_username': catalogUsername,
        'files_channel_id': filesChannelId,
        'files_username': filesUsername,
      },
    );
  }

  String? _emptyToNull(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

class CommunityCatalogRepositoryException implements Exception {
  final String message;

  const CommunityCatalogRepositoryException(this.message);

  @override
  String toString() => message;
}
