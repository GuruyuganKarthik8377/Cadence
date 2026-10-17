import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'services/push_service.dart';
import 'services/reminder_service.dart';
import 'services/timezone_service.dart';
import 'services/widget_service.dart';
import 'theme/app_theme.dart';
import 'features/auth/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (SupabaseConfig.url.isEmpty || SupabaseConfig.anonKey.isEmpty) {
    runApp(const _MissingConfigApp());
    return;
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  // Best-effort: disables itself when Firebase isn't configured.
  await PushService.instance.init();

  // On-device habit reminders. Independent of Firebase — these work offline.
  await ReminderService.instance.init();

  await WidgetService.init();

  // Keep the server's idea of "what time is 08:00 for this user" accurate,
  // now and on every future sign-in.
  await TimezoneService.instance.sync();
  supabase.auth.onAuthStateChange.listen((state) {
    if (state.session != null) TimezoneService.instance.sync();
  });

  runApp(const ProviderScope(child: CadenceApp()));
}

/// Shown instead of crashing when lib/config/supabase_config.dart hasn't
/// been filled in yet.
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Scaffold(
        backgroundColor: AppPalette.light.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Supabase is not configured yet.\n\n'
              'Add your project URL and anon key to\n'
              'lib/config/supabase_config.dart and restart.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                height: 1.6,
                color: AppPalette.light.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CadenceApp extends ConsumerWidget {
  const CadenceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    // Status bar/nav bar icons must follow the effective brightness.
    final platformDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && platformDark);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return MaterialApp(
      title: 'Cadence',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const AuthGate(),
    );
  }
}
