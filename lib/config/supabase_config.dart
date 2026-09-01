class SupabaseConfig {
  SupabaseConfig._();

  static const String url =
      String.fromEnvironment(
    'SUPABASE_URL',
  );

  static const String publishableKey =
      String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get isConfigured =>
      url.trim().isNotEmpty &&
      publishableKey.trim().isNotEmpty;
}
