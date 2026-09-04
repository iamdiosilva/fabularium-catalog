import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/community/application/community_auth_service.dart';
import 'download_queue_service.dart';
import 'supabase_service.dart';
import 'telegram_service.dart';

enum FabulariumSessionStage {
  initializing,
  fabulariumAuthentication,
  telegramAuthentication,
  ready,
  configurationError,
}

class FabulariumSessionService
    extends ChangeNotifier {
  FabulariumSessionService._();

  static final FabulariumSessionService instance =
      FabulariumSessionService._();

  static const bool telegramRequired =
      true;

  final CommunityAuthService _auth =
      CommunityAuthService.instance;

  final TelegramService _telegram =
      TelegramService.instance;

  final DownloadQueueService _downloads =
      DownloadQueueService.instance;

  StreamSubscription<TelegramAuthState>?
      _telegramSubscription;

  bool _initialized =
      false;

  bool _fabulariumConfirmedForRun =
      false;

  bool _signingOut =
      false;

  Object? _error;

  bool get isInitialized =>
      _initialized;

  bool get isSigningOut =>
      _signingOut;

  bool get isFabulariumConfirmedForRun =>
      _fabulariumConfirmedForRun;

  Object? get error =>
      _error;

  CommunityAuthService get auth =>
      _auth;

  TelegramService get telegram =>
      _telegram;

  bool get isReady =>
      stage ==
      FabulariumSessionStage.ready;

  FabulariumSessionStage get stage {
    if (!_initialized) {
      return FabulariumSessionStage
          .initializing;
    }

    if (!SupabaseService
            .instance.isConfigured ||
        !SupabaseService
            .instance.isInitialized) {
      return FabulariumSessionStage
          .configurationError;
    }

    if (!_auth.isSignedIn ||
        !_fabulariumConfirmedForRun) {
      return FabulariumSessionStage
          .fabulariumAuthentication;
    }

    if (!telegramRequired) {
      return FabulariumSessionStage.ready;
    }

    if (_telegram.isAuthenticated) {
      return FabulariumSessionStage.ready;
    }

    return FabulariumSessionStage
        .telegramAuthentication;
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _telegramSubscription =
        _telegram.stateStream.listen(
      (_) {
        notifyListeners();
      },
    );

    _auth.addListener(
      _onFabulariumAuthChanged,
    );

    // Every desktop process starts at the Fabularium step.
    //
    // If Supabase restored a valid session, the login page will offer
    // "Continue" instead of making the user type credentials again.
    //
    // IMPORTANT: we deliberately do NOT connect Telegram here. Telegram
    // networking starts only after the Telegram page is visible, matching
    // the old flow that was already validated.
    _fabulariumConfirmedForRun =
        false;

    _initialized =
        true;

    notifyListeners();
  }

  void confirmFabulariumSession() {
    if (!_auth.isSignedIn) {
      return;
    }

    _fabulariumConfirmedForRun =
        true;

    _error =
        null;

    notifyListeners();
  }

  Future<void> useAnotherFabulariumAccount() async {
    _fabulariumConfirmedForRun =
        false;

    Object? firstError;

    try {
      try {
        await _downloads
            .resetForSessionEnd();
      } catch (error) {
        firstError ??=
            error;
      }

      try {
        await _telegram.logout();
      } catch (error) {
        firstError ??=
            error;
      }

      try {
        await _auth.signOut();
      } catch (error) {
        firstError ??=
            error;
      }
    } finally {
      _error =
          firstError;

      notifyListeners();
    }

    if (firstError != null) {
      throw FabulariumSessionException(
        'Could not completely change account: '
        '$firstError',
      );
    }
  }

  Future<void> signOutAll() async {
    if (_signingOut) {
      return;
    }

    _signingOut =
        true;

    _fabulariumConfirmedForRun =
        false;

    _error =
        null;

    notifyListeners();

    Object? firstError;

    try {
      try {
        await _downloads
            .resetForSessionEnd();
      } catch (error) {
        firstError ??=
            error;
      }

      try {
        await _telegram.logout();
      } catch (error) {
        firstError ??=
            error;
      }

      try {
        await _auth.signOut();
      } catch (error) {
        firstError ??=
            error;
      }
    } finally {
      _signingOut =
          false;

      _error =
          firstError;

      notifyListeners();
    }

    if (firstError != null) {
      throw FabulariumSessionException(
        'The session was closed with an error: '
        '$firstError',
      );
    }
  }

  void _onFabulariumAuthChanged() {
    if (!_auth.isSignedIn) {
      _fabulariumConfirmedForRun =
          false;
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _auth.removeListener(
      _onFabulariumAuthChanged,
    );

    _telegramSubscription
        ?.cancel();

    _telegramSubscription =
        null;

    super.dispose();
  }
}

class FabulariumSessionException
    implements Exception {
  final String message;

  const FabulariumSessionException(
    this.message,
  );

  @override
  String toString() =>
      message;
}
