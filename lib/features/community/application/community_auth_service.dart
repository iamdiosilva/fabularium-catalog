import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/supabase_service.dart';
import '../data/community_repository.dart';
import '../domain/community_profile.dart';

class CommunitySignUpResult {
  final bool needsEmailConfirmation;

  const CommunitySignUpResult({
    required this.needsEmailConfirmation,
  });
}

class CommunityAuthService
    extends ChangeNotifier {
  CommunityAuthService._();

  static final CommunityAuthService instance =
      CommunityAuthService._();

  final CommunityRepository _repository =
      CommunityRepository.instance;

  StreamSubscription<AuthState>?
      _authSubscription;

  bool _initialized = false;
  bool _isLoading = false;
  User? _user;
  CommunityProfile? _profile;
  bool _isAdmin = false;
  Object? _error;

  bool get isInitialized =>
      _initialized;

  bool get isLoading =>
      _isLoading;

  bool get isSignedIn =>
      _user != null;

  User? get user =>
      _user;

  CommunityProfile? get profile =>
      _profile;

  bool get isAdmin =>
      _isAdmin;

  Object? get error =>
      _error;

  String? get email =>
      _user?.email;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _initialized = true;

    final client =
        SupabaseService.instance.client;

    if (client == null) {
      notifyListeners();
      return;
    }

    _user = client.auth.currentUser;

    _authSubscription =
        client.auth.onAuthStateChange.listen(
      (state) {
        _user = state.session?.user;

        unawaited(
          _reloadCommunityIdentity(),
        );
      },
    );

    await _reloadCommunityIdentity();
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    final client = _requireClient();

    _setLoading(true);

    try {
      _error = null;

      final response =
          await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      _user = response.user;

      await _reloadCommunityIdentity(
        notifyAtStart: false,
      );
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<CommunitySignUpResult> signUp({
    required String email,
    required String password,
    required String username,
    required String displayName,
  }) async {
    final client = _requireClient();
    final normalizedUsername =
        _normalizeUsername(username);

    _validateUsername(
      normalizedUsername,
    );

    _setLoading(true);

    try {
      _error = null;

      final response =
          await client.auth.signUp(
        email: email.trim(),
        password: password,
        data: <String, dynamic>{
          'username': normalizedUsername,
          'display_name':
              displayName.trim(),
        },
      );

      _user = response.session?.user;

      if (_user != null) {
        await _reloadCommunityIdentity(
          notifyAtStart: false,
        );
      }

      return CommunitySignUpResult(
        needsEmailConfirmation:
            response.session == null,
      );
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signOut() async {
    final client = _requireClient();

    _setLoading(true);

    try {
      await client.auth.signOut();

      _user = null;
      _profile = null;
      _isAdmin = false;
      _error = null;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> refresh() async {
    await _reloadCommunityIdentity();
  }

  Future<void> updateProfile({
    required String username,
    required String displayName,
    String? avatarUrl,
    String? bio,
  }) async {
    final currentUser = _user;

    if (currentUser == null) {
      throw const CommunityAuthException(
        'Sign in before editing your profile.',
      );
    }

    final normalizedUsername =
        _normalizeUsername(username);

    _validateUsername(
      normalizedUsername,
    );

    if (displayName.trim().isEmpty) {
      throw const CommunityAuthException(
        'Display name is required.',
      );
    }

    _setLoading(true);

    try {
      await _repository.updateProfile(
        userId: currentUser.id,
        username: normalizedUsername,
        displayName: displayName.trim(),
        avatarUrl: avatarUrl,
        bio: bio,
      );

      await _reloadCommunityIdentity(
        notifyAtStart: false,
      );
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _reloadCommunityIdentity({
    bool notifyAtStart = true,
  }) async {
    if (notifyAtStart) {
      _setLoading(true);
    }

    try {
      final currentUser =
          SupabaseService.instance
              .client
              ?.auth
              .currentUser;

      _user = currentUser;

      if (currentUser == null) {
        _profile = null;
        _isAdmin = false;
        _error = null;
        return;
      }

      _profile =
          await _repository.loadProfile(
        currentUser.id,
      );

      _isAdmin =
          await _repository
              .isCurrentUserAdmin();

      _error = null;
    } catch (error) {
      _error = error;
    } finally {
      if (notifyAtStart) {
        _setLoading(false);
      } else {
        notifyListeners();
      }
    }
  }

  SupabaseClient _requireClient() {
    final client =
        SupabaseService.instance.client;

    if (client == null) {
      throw const CommunityAuthException(
        'Supabase is not configured or initialized.',
      );
    }

    return client;
  }

  void _setLoading(
    bool value,
  ) {
    _isLoading = value;
    notifyListeners();
  }

  String _normalizeUsername(
    String value,
  ) {
    return value
        .trim()
        .toLowerCase();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;
    super.dispose();
  }

  void _validateUsername(
    String value,
  ) {
    final valid = RegExp(
      r'^[a-z0-9_]{3,24}$',
    ).hasMatch(value);

    if (!valid) {
      throw const CommunityAuthException(
        'Username must have 3-24 characters using only lowercase letters, numbers and underscore.',
      );
    }
  }
}

class CommunityAuthException
    implements Exception {
  final String message;

  const CommunityAuthException(
    this.message,
  );

  @override
  String toString() => message;
}
