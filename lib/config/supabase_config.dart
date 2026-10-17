import 'package:flutter/foundation.dart' show kIsWeb;

// Fill these in from your Supabase project: Project Settings → API.
// The anon key is designed to be public — access control is enforced by the
// RLS policies in supabase/schema.sql, not by keeping this key secret.
class SupabaseConfig {
  static const String url = 'https://dsrhmrpqscwkeygmguza.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRzcmhtcnBxc2N3a2V5Z21ndXphIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQwMzAzODMsImV4cCI6MjA5OTYwNjM4M30.gTx26uSVOOSHseTuRit6cpFItxLecfavn1ZZYGU_DtM';

  /// Deep link that email confirmation / password recovery links open.
  /// Must be allowlisted in the Supabase dashboard (Authentication →
  /// URL Configuration → Redirect URLs). Web uses the site URL default.
  static String? get authRedirectUrl =>
      kIsWeb ? null : 'cadence://auth-callback';
}
