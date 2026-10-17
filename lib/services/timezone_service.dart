import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import '../providers/auth_provider.dart';

/// Keeps `profiles.timezone` in sync with the device.
///
/// Habit reminder times are stored as local wall-clock ("08:00"), so the
/// backend needs to know which timezone that means. Refreshed on every launch,
/// which also covers the user travelling or a DST change.
class TimezoneService {
  TimezoneService._();
  static final instance = TimezoneService._();

  String? _lastSynced;

  Future<void> sync() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final tz = await FlutterTimezone.getLocalTimezone();
      final name = tz.identifier;
      if (name.isEmpty || name == _lastSynced) return;
      await supabase
          .from('profiles')
          .update({'timezone': name}).eq('id', userId);
      _lastSynced = name;
    } catch (e) {
      // Non-fatal: the backend falls back to UTC.
      debugPrint('timezone sync skipped: $e');
    }
  }
}
