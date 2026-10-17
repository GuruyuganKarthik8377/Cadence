import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:cadence/models/habit.dart';
import 'package:cadence/services/reminder_service.dart';

/// Follow-up reminders ("keep nagging until it's done") and the quiet-hours
/// window that silences them overnight.
void main() {
  Habit habit({
    TimeOfDay? reminderTime = const TimeOfDay(hour: 8, minute: 0),
    bool repeatUntilDone = false,
    int interval = 30,
    int maxCount = 3,
  }) =>
      Habit(
        id: 'habit-1',
        name: 'Read',
        iconOrEmoji: 'bookOpen',
        category: 'Learning',
        habitType: HabitType.build,
        frequency: FrequencyType.daily,
        reminderEnabled: true,
        reminderTime: reminderTime,
        repeatUntilDone: repeatUntilDone,
        repeatIntervalMinutes: interval,
        repeatMaxCount: maxCount,
      );

  group('followUpSlots', () {
    test('a habit without repeat gets only its own reminder', () {
      final slots = ReminderService.followUpSlots(habit());
      expect(slots, hasLength(1));
      expect(slots.single.index, 0);
      expect(slots.single.time, const TimeOfDay(hour: 8, minute: 0));
    });

    test('repeat adds exactly maxCount follow-ups after the reminder', () {
      final slots = ReminderService.followUpSlots(
        habit(repeatUntilDone: true, interval: 30, maxCount: 3),
      );
      expect(slots.map((s) => s.time), [
        const TimeOfDay(hour: 8, minute: 0), // the reminder itself
        const TimeOfDay(hour: 8, minute: 30),
        const TimeOfDay(hour: 9, minute: 0),
        const TimeOfDay(hour: 9, minute: 30),
      ]);
    });

    test('a custom interval is honoured', () {
      final slots = ReminderService.followUpSlots(
        habit(repeatUntilDone: true, interval: 15, maxCount: 2),
      );
      expect(slots.map((s) => s.time), [
        const TimeOfDay(hour: 8, minute: 0),
        const TimeOfDay(hour: 8, minute: 15),
        const TimeOfDay(hour: 8, minute: 30),
      ]);
    });

    test('follow-ups crossing midnight report the day they land on', () {
      // 23:20 + 30 + 30 + 30 → 23:50, 00:20 (next day), 00:50 (next day).
      final slots = ReminderService.followUpSlots(
        habit(
          reminderTime: const TimeOfDay(hour: 23, minute: 20),
          repeatUntilDone: true,
          interval: 30,
          maxCount: 3,
        ),
      );
      expect(slots.map((s) => (s.time.hour, s.time.minute, s.dayShift)), [
        (23, 20, 0),
        (23, 50, 0),
        (0, 20, 1),
        (0, 50, 1),
      ]);
    });

    test('maxCount is clamped to the id field width', () {
      final slots = ReminderService.followUpSlots(
        habit(repeatUntilDone: true, maxCount: 99),
      );
      expect(slots.length, ReminderService.maxFollowUps + 1);
    });

    test('a habit with no reminder time has no slots', () {
      expect(ReminderService.followUpSlots(habit(reminderTime: null)), isEmpty);
    });
  });

  group('inQuietHours', () {
    const start = TimeOfDay(hour: 22, minute: 0);
    const end = TimeOfDay(hour: 7, minute: 0);

    test('a window that wraps midnight covers both sides of it', () {
      expect(ReminderService.inQuietHours(
          const TimeOfDay(hour: 23, minute: 0), start, end), isTrue);
      expect(ReminderService.inQuietHours(
          const TimeOfDay(hour: 2, minute: 0), start, end), isTrue);
    });

    test('daytime is outside the wrapping window', () {
      expect(ReminderService.inQuietHours(
          const TimeOfDay(hour: 12, minute: 0), start, end), isFalse);
    });

    test('boundaries: start is inside, end is outside', () {
      expect(ReminderService.inQuietHours(start, start, end), isTrue);
      expect(ReminderService.inQuietHours(end, start, end), isFalse);
    });

    test('a same-day window works too', () {
      const s = TimeOfDay(hour: 9, minute: 0);
      const e = TimeOfDay(hour: 17, minute: 0);
      expect(ReminderService.inQuietHours(
          const TimeOfDay(hour: 12, minute: 0), s, e), isTrue);
      expect(ReminderService.inQuietHours(
          const TimeOfDay(hour: 8, minute: 0), s, e), isFalse);
    });

    test('null bounds or a zero-width window mean quiet hours are off', () {
      const noon = TimeOfDay(hour: 12, minute: 0);
      expect(ReminderService.inQuietHours(noon, null, end), isFalse);
      expect(ReminderService.inQuietHours(noon, start, null), isFalse);
      expect(ReminderService.inQuietHours(noon, start, start), isFalse);
    });
  });

  group('notificationId', () {
    test('is stable for the same habit, weekday and follow-up', () {
      expect(ReminderService.notificationId('abc', 3, 2),
          ReminderService.notificationId('abc', 3, 2));
    });

    test('separates weekday and follow-up without overlapping', () {
      final ids = <int>{};
      for (var weekday = 0; weekday <= 7; weekday++) {
        for (var followUp = 0;
            followUp <= ReminderService.maxFollowUps;
            followUp++) {
          ids.add(ReminderService.notificationId(
              'same-habit', weekday == 0 ? null : weekday, followUp));
        }
      }
      // 8 weekday slots × 6 follow-up slots, all distinct.
      expect(ids, hasLength(8 * 6));
    });

    test('stays inside int32 for a realistic uuid', () {
      final id = ReminderService.notificationId(
          'f47ac10b-58cc-4372-a567-0e02b2c3d479', 7, 5);
      expect(id, lessThan(1 << 31));
      expect(id, greaterThanOrEqualTo(0));
    });

    test('different habits do not share a slot', () {
      expect(ReminderService.notificationId('habit-a', 1, 0),
          isNot(ReminderService.notificationId('habit-b', 1, 0)));
    });
  });
}
