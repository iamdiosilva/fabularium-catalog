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

  // V3.4.1 treats Telegram as part of the complete Fabularium session.
  // If the product later supports a browse-only mode, this can become
  // configurable without changing the authentication screens.
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

  bool _checkingTelegram =
      false;

  bool _signingOut =
      false;

  bool _clearingOrphanTelegram =
      false;

  Object? _error;

  bool get isInitialized =>
      _initialized;

  bool get isCheckingTelegram =>
      _checkingTelegram;

  bool get isSigningOut =>
      _signingOut;

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

    if (!_auth.isSignedIn) {
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

    _initialized =
        true;

    try {
      if (_auth.isSignedIn) {
        await ensureTelegramSession();
      } else {
        await _clearOrphanTelegramSession();
      }

      _error =
          null;
    } catch (error) {
      _error =
          error;
    } finally {
      notifyListeners();
    }
  }

  Future<void> ensureTelegramSession() async {
    if (!telegramRequired ||
        !_auth.isSignedIn ||
        _telegram.isAuthenticated ||
        _checkingTelegram) {
      return;
    }

    _checkingTelegram =
        true;

    _error =
        null;

    notifyListeners();

    try {
      await _telegram.connect();
    } catch (error) {
      _error =
          error;
    } finally {
      _checkingTelegram =
          false;

      notifyListeners();
    }
  }

  Future<void> signOutAll() async {
    if (_signingOut) {
      return;
    }

    _signingOut =
        true;

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

  Future<void> _clearOrphanTelegramSession() async {
    if (_clearingOrphanTelegram ||
        _auth.isSignedIn) {
      return;
    }

    if (!_telegram.hasSavedSession &&
        !_telegram.isAuthenticated) {
      return;
    }

    _clearingOrphanTelegram =
        true;

    try {
      await _telegram.logout();
    } finally {
      _clearingOrphanTelegram =
          false;
    }
  }

  void _onFabulariumAuthChanged() {
    notifyListeners();

    if (_signingOut) {
      return;
    }

    if (_auth.isSignedIn) {
      unawaited(
        ensureTelegramSession(),
      );

      return;
    }

    unawaited(
      _clearOrphanTelegramSession(),
    );
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
