class SupabaseConfig {
  const SupabaseConfig._();

  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://gaifxtuintzftkgqomue.supabase.co',
  );

  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_p1FfxpQZUzMLM35fxSwP6w_hQAj4rQY',
  );

  static bool get isConfigured =>
      url.startsWith('https://') &&
      publishableKey.startsWith('sb_publishable_');
}
