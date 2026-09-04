import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/supabase_service.dart';
import '../domain/community_profile.dart';
import '../domain/community_submission.dart';

class CommunityRepository {
  CommunityRepository._();

  static final CommunityRepository instance =
      CommunityRepository._();

  static const String _submissionSelect =
      'id,submitted_by,name,studio,category,model_type,scale,height,'
      'description,tags,status,duplicate_status,duplicate_of_model_id,'
      'source_folder_name,source_size,archive_file_name,archive_size,'
      'archive_sha256,content_fingerprint,published_model_id,'
      'published_package_id,submitted_at,updated_at,uploaded_at,'
      'reviewed_at,reviewed_by,review_note,published_at,upload_error';

  SupabaseClient get _client {
    final client =
        SupabaseService.instance.client;

    if (client == null) {
      throw const CommunityRepositoryException(
        'Supabase is not initialized.',
      );
    }

    return client;
  }

  Future<CommunityProfile?> loadProfile(
    String userId,
  ) async {
    final raw = await _client
        .from('fabularium_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (raw == null) {
      return null;
    }

    return CommunityProfile.fromJson(
      Map<String, dynamic>.from(raw),
    );
  }

  Future<bool> isCurrentUserAdmin() async {
    final raw =
        await _client.rpc(
      'is_fabularium_admin',
    );

    if (raw is bool) {
      return raw;
    }

    return raw
            ?.toString()
            .toLowerCase() ==
        'true';
  }

  Future<void> updateProfile({
    required String userId,
    required String username,
    required String displayName,
    String? avatarUrl,
    String? bio,
  }) async {
    await _client
        .from(
          'fabularium_profiles',
        )
        .update(
          <String, dynamic>{
            'username': username,
            'display_name':
                displayName,
            'avatar_url':
                _emptyToNull(
              avatarUrl,
            ),
            'bio':
                _emptyToNull(
              bio,
            ),
          },
        )
        .eq(
          'user_id',
          userId,
        );
  }

  Future<String> createSubmission({
    required Map<String, dynamic> payload,
  }) async {
    final raw =
        await _client.rpc(
      'create_fabularium_submission',
      params:
          <String, dynamic>{
        'payload':
            payload,
      },
    );

    final id =
        raw?.toString().trim() ??
            '';

    if (id.isEmpty) {
      throw const CommunityRepositoryException(
        'Supabase did not return the submission ID.',
      );
    }

    return id;
  }

  Future<List<CommunitySubmission>>
      loadMySubmissions() async {
    final user =
        _client.auth.currentUser;

    if (user == null) {
      return const <
          CommunitySubmission>[];
    }

    final raw =
        await _client
            .from(
              'fabularium_submissions',
            )
            .select(
              _submissionSelect,
            )
            .eq(
              'submitted_by',
              user.id,
            )
            .order(
              'submitted_at',
              ascending: false,
            );

    return _mapSubmissions(
      raw,
    );
  }

  Future<CommunitySubmission?>
      loadSubmission(
    String submissionId,
  ) async {
    final raw =
        await _client
            .from(
              'fabularium_submissions',
            )
            .select(
              _submissionSelect,
            )
            .eq(
              'id',
              submissionId,
            )
            .maybeSingle();

    if (raw == null) {
      return null;
    }

    return CommunitySubmission.fromJson(
      Map<String, dynamic>.from(
        raw,
      ),
    );
  }

  Future<List<CommunitySubmission>>
      loadModerationQueue() async {
    final raw =
        await _client
            .from(
              'fabularium_submissions',
            )
            .select(
              _submissionSelect,
            )
            .inFilter(
              'status',
              <String>[
                'pending_review',
                'duplicate_suspected',
                'approved',
                'publishing',
              ],
            )
            .order(
              'submitted_at',
              ascending: true,
            );

    return _mapSubmissions(
      raw,
    );
  }

  Future<void> reviewSubmission({
    required String submissionId,
    required String decision,
    String? note,
    String? duplicateOfModelId,
  }) async {
    await _client.rpc(
      'review_fabularium_submission',
      params:
          <String, dynamic>{
        'target_submission_id':
            submissionId,
        'decision':
            decision,
        'note':
            _emptyToNull(
          note,
        ),
        'duplicate_of':
            _emptyToNull(
          duplicateOfModelId,
        ),
      },
    );
  }

  Future<void> analyzeSubmission(
    String submissionId,
  ) async {
    await _client.rpc(
      'analyze_fabularium_submission',
      params:
          <String, dynamic>{
        'target_submission_id':
            submissionId,
      },
    );
  }

  Future<bool> hasLikedModel(
    String modelId,
  ) async {
    final user =
        _client.auth.currentUser;

    if (user == null) {
      return false;
    }

    final raw =
        await _client
            .from(
              'fabularium_likes',
            )
            .select(
              'model_id',
            )
            .eq(
              'model_id',
              modelId,
            )
            .eq(
              'user_id',
              user.id,
            )
            .maybeSingle();

    return raw != null;
  }

  Future<int> loadModelLikeCount(
    String modelId,
  ) async {
    final raw =
        await _client
            .from(
              'fabularium_likes',
            )
            .select(
              'user_id',
            )
            .eq(
              'model_id',
              modelId,
            );

    return raw.length;
  }

  Future<void> likeModel(
    String modelId,
  ) async {
    final user =
        _client.auth.currentUser;

    if (user == null) {
      throw const CommunityRepositoryException(
        'Sign in before liking a model.',
      );
    }

    await _client
        .from(
          'fabularium_likes',
        )
        .insert(
          <String, dynamic>{
            'model_id':
                modelId,
            'user_id':
                user.id,
          },
        );
  }

  Future<void> unlikeModel(
    String modelId,
  ) async {
    final user =
        _client.auth.currentUser;

    if (user == null) {
      return;
    }

    await _client
        .from(
          'fabularium_likes',
        )
        .delete()
        .eq(
          'model_id',
          modelId,
        )
        .eq(
          'user_id',
          user.id,
        );
  }

  List<CommunitySubmission>
      _mapSubmissions(
    dynamic raw,
  ) {
    if (raw is! List) {
      return const <
          CommunitySubmission>[];
    }

    final result =
        <CommunitySubmission>[];

    for (final item in raw) {
      if (item is Map) {
        result.add(
          CommunitySubmission.fromJson(
            Map<String, dynamic>.from(
              item,
            ),
          ),
        );
      }
    }

    return result;
  }

  String? _emptyToNull(
    String? value,
  ) {
    final text =
        value?.trim() ?? '';

    return text.isEmpty
        ? null
        : text;
  }
}

class CommunityRepositoryException
    implements Exception {
  final String message;

  const CommunityRepositoryException(
    this.message,
  );

  @override
  String toString() =>
      message;
}
