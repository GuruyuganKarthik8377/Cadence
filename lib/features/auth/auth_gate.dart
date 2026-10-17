import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/habit_provider.dart';
import '../../services/offline_cache.dart';
import '../../services/reminder_service.dart';
import '../../services/widget_service.dart';
import '../../theme/app_theme.dart';
import '../home/home_page.dart';
import '../onboarding/onboarding_page.dart';
import 'reset_password_page.dart';
import 'sign_in_page.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  // Set when a password-recovery deep link opens the app; cleared once the
  // user finishes updating their password.
  bool _inPasswordRecovery = false;
  StreamSubscription<Uri?>? _widgetClicks;

  @override
  void initState() {
    super.initState();
    // A widget tap that launched the app, plus any that arrive while it runs.
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_handleWidgetLaunch);
    _widgetClicks = HomeWidget.widgetClicked.listen(_handleWidgetLaunch);
  }

  @override
  void dispose() {
    _widgetClicks?.cancel();
    super.dispose();
  }

  /// Completes the tapped habit. Marks rather than toggles: tapping a habit on
  /// the widget means "done", never "undo" — the widget has no confirmation
  /// step to make an accidental un-completion recoverable.
  Future<void> _handleWidgetLaunch(Uri? uri) async {
    final habitId = WidgetService.habitIdFromUri(uri);
    if (habitId == null) return;
    if (supabase.auth.currentSession == null) return;
    try {
      await ref.read(habitsProvider.notifier).ensureCompletedToday(habitId);
    } catch (_) {
      // Best-effort: the habit may have been deleted, or a server-side gate
      // (run/walk verification) may refuse it.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateChangesProvider, (previous, next) {
      final event = next.valueOrNull?.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        setState(() => _inPasswordRecovery = true);
      } else if (event == AuthChangeEvent.signedOut) {
        setState(() => _inPasswordRecovery = false);
        // Don't keep nagging someone who signed out.
        ReminderService.instance.cancelAll();
        // Never let one account's cached habits show up under another.
        OfflineCache.clearHabits();
      }
    });

    final authState = ref.watch(authStateChangesProvider);

    // Kept alive here so reminders stay scheduled and the home screen widget
    // stays current for the whole session.
    ref.watch(reminderSyncProvider);
    ref.watch(widgetSyncProvider);

    if (_inPasswordRecovery) {
      return ResetPasswordPage(
        onDone: () => setState(() => _inPasswordRecovery = false),
      );
    }

    return authState.when(
      data: (state) {
        final session = state.session ?? supabase.auth.currentSession;
        return session != null ? const _SignedInGate() : const SignInPage();
      },
      loading: () => Scaffold(
        backgroundColor: context.colors.background,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const SignInPage(),
    );
  }
}

/// Shows onboarding once, while the account has zero habits, then HomePage.
/// No persisted "seen it" flag: adding a habit — through onboarding or by
/// skipping it — is itself what makes the gate stop tripping.
class _SignedInGate extends ConsumerStatefulWidget {
  const _SignedInGate();

  @override
  ConsumerState<_SignedInGate> createState() => _SignedInGateState();
}

class _SignedInGateState extends ConsumerState<_SignedInGate> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final habitsAsync = ref.watch(habitsProvider);
    final habits = habitsAsync.valueOrNull;

    if (!_dismissed && habits != null && habits.isEmpty) {
      return OnboardingPage(onDone: () => setState(() => _dismissed = true));
    }
    return const HomePage();
  }
}
