import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/habit.dart';

/// On-device habit reminders.
///
/// These are scheduled locally rather than pushed from the server: a reminder
/// is a purely local, time-based event, so it needs no Firebase project, no
/// edge function and no cron — and it still fires with the phone offline.
///
/// Scheduling is all-or-nothing. Any habit change cancels every pending
/// reminder and reschedules from the current list, which keeps us from having
/// to track which notification ids belong to which habit.
class ReminderService {
  ReminderService._();
  static final instance = ReminderService._();

  static const _channelId = 'habit_reminders';

  /// Hard ceiling on follow-ups per reminder. Also the width of the id field,
  /// so raising it means widening [notificationId].
  ///
  /// ponytail: Android caps pending alarms at roughly 500 per app. Worst case
  /// here is 7 weekdays × 6 slots = 42 per habit, so ~11 habits with daily
  /// nagging on every weekday would approach it. Fine for a habit tracker;
  /// batch into a single re-arming alarm if anyone ever hits it.
  static const maxFollowUps = 5;
  final _plugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool available = false;

  /// Call once at startup. Safe to call more than once.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      tzdata.initializeTimeZones();
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      available = true;
    } catch (e) {
      // Reminders are best-effort; never break launch over them.
      debugPrint('reminder init skipped: $e');
      available = false;
    }
  }

  /// Asks for the Android 13+ notification permission. Returns true if we can
  /// post notifications.
  Future<bool> requestPermission() async {
    if (!available) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    return await android.requestNotificationsPermission() ?? false;
  }

  /// Rebuilds every pending reminder from [habits].
  ///
  /// [enabled] is the account-level switch from the profile — when it's off we
  /// still clear, so turning it off takes effect immediately.
  Future<void> rescheduleAll(
    List<Habit> habits, {
    required bool enabled,
    TimeOfDay? quietStart,
    TimeOfDay? quietEnd,
  }) async {
    if (!available) return;
    try {
      await _plugin.cancelAll();
      if (!enabled) return;

      final due = habits
          .where((h) => h.reminderEnabled && h.reminderTime != null)
          .toList();
      if (due.isEmpty) return;

      // Ask only once we actually have something to post. This lands right
      // after the user saves a habit with a reminder, so the system prompt
      // still reads as a consequence of what they just did.
      if (!await requestPermission()) return;

      for (final habit in due) {
        await _schedule(habit, quietStart: quietStart, quietEnd: quietEnd);
      }
    } catch (e) {
      debugPrint('reminder reschedule failed: $e');
    }
  }

  Future<void> cancelAll() async {
    if (!available) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  Future<void> _schedule(
    Habit habit, {
    TimeOfDay? quietStart,
    TimeOfDay? quietEnd,
    tz.TZDateTime? from,
  }) async {
    final time = habit.reminderTime;
    if (!habit.reminderEnabled || time == null) return;

    // "Repeat reminder daily" overrides the schedule — nag every day.
    // Otherwise remind only on days the habit is actually due. timesPerWeek
    // habits have no fixed days, so they get a daily nudge either way.
    final everyDay = habit.repeatReminderDaily ||
        habit.frequency != FrequencyType.specificDays;

    final baseWeekdays = everyDay
        ? <int?>[null]
        : [
            for (final day in habit.specificDays)
              if (day >= 0 && day <= 6) day + 1, // 0=Mon → DateTime.monday
          ];

    for (final weekday in baseWeekdays) {
      for (final slot in followUpSlots(habit)) {
        // Quiet hours silence the nagging, never the reminder the user
        // actually asked for.
        if (slot.index > 0 &&
            inQuietHours(slot.time, quietStart, quietEnd)) {
          continue;
        }
        // A follow-up that rolls past midnight belongs to the next day, so a
        // Monday 23:40 habit nags on Tuesday rather than 23 hours early.
        final shifted = weekday == null
            ? null
            : ((weekday - 1 + slot.dayShift) % 7) + 1;
        await _scheduleAt(habit, slot.time,
            weekday: shifted, followUp: slot.index, from: from);
      }
    }
  }

  /// The reminder plus its follow-ups, as wall-clock times.
  ///
  /// Index 0 is the habit's own reminder time; 1..n are the nags. [dayShift]
  /// counts how many midnights the slot crossed.
  @visibleForTesting
  static List<({int index, TimeOfDay time, int dayShift})> followUpSlots(
      Habit habit) {
    final base = habit.reminderTime;
    if (base == null) return const [];

    final count = habit.repeatUntilDone
        ? habit.repeatMaxCount.clamp(1, maxFollowUps)
        : 0;
    final interval = habit.repeatIntervalMinutes.clamp(5, 240);

    return [
      for (var i = 0; i <= count; i++)
        () {
          final total = base.hour * 60 + base.minute + interval * i;
          final within = total % 1440;
          return (
            index: i,
            time: TimeOfDay(hour: within ~/ 60, minute: within % 60),
            dayShift: total ~/ 1440,
          );
        }(),
    ];
  }

  /// Whether [t] falls inside the do-not-disturb window. A window that wraps
  /// midnight (22:00 → 07:00) is handled. Null bounds, or a zero-width
  /// window, mean quiet hours are off.
  @visibleForTesting
  static bool inQuietHours(TimeOfDay t, TimeOfDay? start, TimeOfDay? end) {
    if (start == null || end == null) return false;
    final s = start.hour * 60 + start.minute;
    final e = end.hour * 60 + end.minute;
    if (s == e) return false;
    final m = t.hour * 60 + t.minute;
    return s < e ? (m >= s && m < e) : (m >= s || m < e);
  }

  Future<void> _scheduleAt(
    Habit habit,
    TimeOfDay time, {
    required int? weekday,
    int followUp = 0,
    tz.TZDateTime? from,
  }) async {
    await _plugin.zonedSchedule(
      id: notificationId(habit.id, weekday, followUp),
      title: habit.name,
      body: _body(habit, followUp: followUp),
      scheduledDate: nextOccurrence(time, weekday, from: from),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Habit reminders',
          channelDescription: 'Reminders at each habit\'s scheduled time',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      // Inexact avoids the SCHEDULE_EXACT_ALARM permission, which Play reviews
      // separately and rejects for anything that isn't an alarm clock. A habit
      // nudge a few minutes late is fine.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: weekday == null
          ? DateTimeComponents.time
          : DateTimeComponents.dayOfWeekAndTime,
    );
  }

  String _body(Habit habit, {int followUp = 0}) {
    final goal = habit.durationValue > 0
        ? ' — ${habit.durationValue} ${habit.durationUnit}'
        : '';
    if (followUp > 0) {
      return 'Still not done$goal. Tap to open Cadence.';
    }
    if (habit.hasLocation) {
      return 'Time to check in at ${habit.locationName}$goal';
    }
    return 'Time for your habit$goal';
  }

  /// The next wall-clock occurrence of [time], optionally pinned to [weekday]
  /// (DateTime.monday..DateTime.sunday). Built in the local zone so DST is
  /// handled by the timezone package rather than by hand.
  @visibleForTesting
  static tz.TZDateTime nextOccurrence(TimeOfDay time, int? weekday,
      {tz.TZDateTime? from}) {
    final now = from ?? tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
        now.location, now.year, now.month, now.day, time.hour, time.minute);
    if (weekday != null) {
      while (next.weekday != weekday) {
        next = next.add(const Duration(days: 1));
      }
    }
    if (!next.isAfter(now)) {
      next = next.add(Duration(days: weekday == null ? 1 : 7));
      // Adding 7×24h can land an hour off across a DST boundary; re-pin the
      // wall-clock time so an 08:00 reminder stays 08:00.
      next = tz.TZDateTime(next.location, next.year, next.month, next.day,
          time.hour, time.minute);
    }
    return next;
  }

  /// Stable 32-bit id for a habit/weekday/follow-up triple. Android
  /// notification ids are int32, and [String.hashCode] isn't guaranteed stable
  /// across runs, so this hashes the UUID itself — the same habit always
  /// reclaims its own slots.
  ///
  /// Layout: hash(23 bits) | weekday(3) | followUp(3). The hash lost three
  /// bits to make room for follow-ups.
  ///
  /// ponytail: 23 bits is 8.4M buckets, so two habits colliding needs ~3400
  /// habits on one account before it's even a percent likely. Widen to a
  /// stored per-habit id column if that ever stops being absurd.
  @visibleForTesting
  static int notificationId(String habitId, int? weekday, [int followUp = 0]) {
    var hash = 0;
    for (final unit in habitId.codeUnits) {
      hash = (hash * 31 + unit) & 0x007fffff;
    }
    return hash * 64 + (weekday ?? 0) * 8 + followUp;
  }

  /// Every notification id [_schedule] could have created for [habit].
  ///
  /// Derived rather than tracked: ids are a pure function of the habit, so
  /// cancelling never needs persisted bookkeeping. Covers all seven weekdays
  /// regardless of the current schedule, so ids left behind by an earlier
  /// configuration are cleaned up too.
  static Iterable<int> _idsFor(Habit habit) sync* {
    for (var weekday = 0; weekday <= 7; weekday++) {
      for (var followUp = 0; followUp <= maxFollowUps; followUp++) {
        yield notificationId(habit.id, weekday == 0 ? null : weekday, followUp);
      }
    }
  }

  /// Goes quiet for the rest of today, then resumes tomorrow.
  ///
  /// Called when a habit is ticked off. Cancelling alone isn't enough: these
  /// are repeating schedules, so a bare cancel would kill the reminder for
  /// every future day too. Cancel, then re-arm anchored past midnight.
  Future<void> silenceForToday(
    Habit habit, {
    TimeOfDay? quietStart,
    TimeOfDay? quietEnd,
  }) async {
    if (!available) return;
    try {
      for (final id in _idsFor(habit)) {
        await _plugin.cancel(id: id);
      }
      final now = tz.TZDateTime.now(tz.local);
      final tomorrow =
          tz.TZDateTime(tz.local, now.year, now.month, now.day + 1);
      await _schedule(habit,
          quietStart: quietStart, quietEnd: quietEnd, from: tomorrow);
    } catch (e) {
      debugPrint('reminder silence failed: $e');
    }
  }
}

/// Opens Android's own per-app notification settings.
///
/// Sound, vibration and importance live in the OS from Android 8 onward —
/// notification channels are immutable once created, so an in-app picker
/// would need a channel per sound and would leave retired ones visible in
/// system settings forever. Handed to the platform instead.
class SystemNotificationSettings {
  static const _channel = MethodChannel('com.harishram.cadence/settings');

  /// Returns false when nothing could handle the intent (or off-Android),
  /// so the caller can say so rather than appearing to do nothing.
  static Future<bool> open() async {
    try {
      return await _channel.invokeMethod<bool>('openNotificationSettings') ??
          false;
    } catch (_) {
      return false;
    }
  }
}
