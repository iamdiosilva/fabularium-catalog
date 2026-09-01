import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class SupabaseService {
  SupabaseService._();

  static final SupabaseService instance =
      SupabaseService._();

  bool _initialized = false;
  Object? _initializationError;

  bool get isConfigured =>
      SupabaseConfig.isConfigured;

  bool get isInitialized =>
      _initialized;

  Object? get initializationError =>
      _initializationError;

  SupabaseClient? get client {
    if (!_initialized) {
      return null;
    }

    return Supabase.instance.client;
  }

  Future<void> initialize() async {
    if (_initialized ||
        !SupabaseConfig.isConfigured) {
      return;
    }

    try {
      await Supabase.initialize(
        url:
            SupabaseConfig.url,
        publishableKey:
            SupabaseConfig.publishableKey,
      );

      _initialized = true;
      _initializationError = null;

      debugPrint(
        '[Supabase] Initialized.',
      );
    } catch (error) {
      _initialized = false;
      _initializationError = error;

      // Supabase is an indexing/catalog layer. A temporary Supabase failure
      // must never prevent the local/Telegram catalog from opening.
      debugPrint(
        '[Supabase] Initialization failed: $error',
      );
    }
  }
}
