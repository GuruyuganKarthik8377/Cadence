import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../providers/auth_provider.dart';

/// Push notifications via FCM. The app must run fine WITHOUT Firebase
/// configured (no google-services.json yet), so everything here is
/// best-effort: init failures flip [enabled] to false and the rest of the
/// app never notices.
class PushService {
  PushService._();
  static final instance = PushService._();

  bool _initialized = false;
  bool enabled = false;

  /// Call once at startup, after Supabase.initialize. Safe to call when
  /// Firebase isn't configured — it just disables push.
  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;
    try {
      await Firebase.initializeApp();
      enabled = true;
    } catch (_) {
      // No google-services.json / Firebase project yet: push stays off.
      enabled = false;
      return;
    }

    // Keep the stored token fresh.
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _storeToken(token);
    });

    // Store a token now if someone is already signed in, and again on
    // every future sign-in.
    supabase.auth.onAuthStateChange.listen((state) {
      if (state.session != null) syncToken();
    });
    if (supabase.auth.currentSession != null) {
      await syncToken();
    }
  }

  /// Ask for permission (Android 13+ shows the system prompt) and upsert
  /// the device token for the signed-in user.
  Future<void> syncToken() async {
    if (!enabled) return;
    try {
      final settings =
          await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _storeToken(token);
    } catch (_) {
      // Push is best-effort; never break the app over it.
    }
  }

  Future<void> _storeToken(String token) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await supabase.from('notification_tokens').upsert(
        {
          'user_id': userId,
          'fcm_token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
        onConflict: 'user_id,platform',
      );
    } catch (_) {}
  }
}
