import 'package:flutter/material.dart' show TimeOfDay;

/// Parses a Postgres `time` column ('22:00:00') into a [TimeOfDay].
TimeOfDay? timeOfDayFromDb(String? s) {
  if (s == null || s.isEmpty) return null;
  final parts = s.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return TimeOfDay(hour: h, minute: m);
}

/// Renders a [TimeOfDay] for a Postgres `time` column.
String? timeOfDayToDb(TimeOfDay? t) => t == null
    ? null
    : '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:00';

class Profile {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool remindersEnabled;
  /// Raw stored balance. Prefer [availableFreezes] — this number is only
  /// meaningful within [freezesRefilledOn]'s month.
  final int freezesRemaining;

  /// When the allowance was last topped up. The top-up is done server-side by
  /// use_freeze() on the first spend of a new month, so between the 1st and
  /// that first spend this is still last month's date.
  final DateTime? freezesRefilledOn;

  /// Short free-text line shown on the profile. Visible to accepted friends.
  final String? bio;

  /// Do-not-disturb window, local wall-clock. Both null means off. The window
  /// may wrap midnight (22:00 → 07:00).
  ///
  /// Suppresses reminder FOLLOW-UPS and nudge push — never a habit's own
  /// reminder time, which the user chose deliberately.
  final TimeOfDay? quietHoursStart;
  final TimeOfDay? quietHoursEnd;

  /// Pre-fills the reminder time when creating a habit. Null = no pre-fill.
  final TimeOfDay? defaultReminderTime;

  static const monthlyFreezes = 2;
  static const maxBioLength = 160;

  bool get hasQuietHours =>
      quietHoursStart != null && quietHoursEnd != null;

  /// Freezes actually spendable right now.
  ///
  /// The client used to refill the balance itself on profile read; that write
  /// privilege is revoked (migration 003), so the refill is inferred here for
  /// display and applied for real by the server when a freeze is spent.
  int get availableFreezes {
    final now = DateTime.now();
    final last = freezesRefilledOn;
    if (last == null || last.year != now.year || last.month != now.month) {
      return monthlyFreezes;
    }
    return freezesRemaining;
  }

  const Profile({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.remindersEnabled = true,
    this.freezesRemaining = monthlyFreezes,
    this.freezesRefilledOn,
    this.bio,
    this.quietHoursStart,
    this.quietHoursEnd,
    this.defaultReminderTime,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      remindersEnabled: json['reminders_enabled'] as bool? ?? true,
      freezesRemaining: json['freezes_remaining'] as int? ?? monthlyFreezes,
      freezesRefilledOn:
          DateTime.tryParse(json['freezes_refilled_on'] as String? ?? ''),
      bio: json['bio'] as String?,
      quietHoursStart: timeOfDayFromDb(json['quiet_hours_start'] as String?),
      quietHoursEnd: timeOfDayFromDb(json['quiet_hours_end'] as String?),
      defaultReminderTime:
          timeOfDayFromDb(json['default_reminder_time'] as String?),
    );
  }
}
