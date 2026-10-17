import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:cadence/services/reminder_service.dart';

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/New_York'));
  });

  tz.TZDateTime at(int y, int m, int d, [int h = 0, int min = 0]) =>
      tz.TZDateTime(tz.local, y, m, d, h, min);

  group('nextOccurrence — daily', () {
    test('later today stays today', () {
      final next = ReminderService.nextOccurrence(
        const TimeOfDay(hour: 20, minute: 0),
        null,
        from: at(2026, 3, 10, 9),
      );
      expect(next.day, 10);
      expect(next.hour, 20);
    });

    test('already past rolls to tomorrow', () {
      final next = ReminderService.nextOccurrence(
        const TimeOfDay(hour: 8, minute: 0),
        null,
        from: at(2026, 3, 10, 9),
      );
      expect(next.day, 11);
      expect(next.hour, 8);
    });

    test('exactly now rolls forward rather than firing instantly', () {
      final next = ReminderService.nextOccurrence(
        const TimeOfDay(hour: 9, minute: 0),
        null,
        from: at(2026, 3, 10, 9),
      );
      expect(next.day, 11);
    });
  });

  group('nextOccurrence — weekly', () {
    test('pins to the requested weekday', () {
      // 2026-03-10 is a Tuesday; ask for Friday.
      final next = ReminderService.nextOccurrence(
        const TimeOfDay(hour: 7, minute: 30),
        DateTime.friday,
        from: at(2026, 3, 10, 9),
      );
      expect(next.weekday, DateTime.friday);
      expect(next.day, 13);
      expect(next.hour, 7);
      expect(next.minute, 30);
    });

    test('same weekday but past rolls a full week, not a day', () {
      final next = ReminderService.nextOccurrence(
        const TimeOfDay(hour: 8, minute: 0),
        DateTime.tuesday,
        from: at(2026, 3, 10, 9),
      );
      expect(next.weekday, DateTime.tuesday);
      expect(next.day, 17);
    });
  });

  group('nextOccurrence — DST', () {
    test('keeps wall-clock time across a spring-forward boundary', () {
      // US DST starts 2026-03-08. Roll a Sunday 08:00 reminder from the
      // Sunday before, so the +7 day jump crosses the transition.
      final next = ReminderService.nextOccurrence(
        const TimeOfDay(hour: 8, minute: 0),
        DateTime.sunday,
        from: at(2026, 3, 1, 9),
      );
      expect(next.weekday, DateTime.sunday);
      expect(next.day, 8);
      // Naive +7×24h arithmetic would land at 07:00 here.
      expect(next.hour, 8);
      expect(next.minute, 0);
    });

    test('keeps wall-clock time across a fall-back boundary', () {
      // US DST ends 2026-11-01.
      final next = ReminderService.nextOccurrence(
        const TimeOfDay(hour: 8, minute: 0),
        DateTime.sunday,
        from: at(2026, 10, 25, 9),
      );
      expect(next.day, 1);
      expect(next.month, 11);
      expect(next.hour, 8);
    });
  });

  group('notificationId', () {
    test('is stable for the same habit and weekday', () {
      const id = '3f2b1c9e-1111-4a2b-9c3d-000000000001';
      expect(ReminderService.notificationId(id, 3),
          ReminderService.notificationId(id, 3));
    });

    test('differs per weekday so a habit can hold several slots', () {
      const id = '3f2b1c9e-1111-4a2b-9c3d-000000000001';
      final ids = {
        for (var d = 1; d <= 7; d++) ReminderService.notificationId(id, d)
      };
      expect(ids.length, 7);
    });

    test('differs between habits', () {
      expect(
        ReminderService.notificationId('aaaaaaaa-0000-0000-0000-000000000001', null),
        isNot(ReminderService.notificationId(
            'bbbbbbbb-0000-0000-0000-000000000002', null)),
      );
    });

    test('always fits in a 32-bit Android notification id', () {
      for (var i = 0; i < 500; i++) {
        final id = ReminderService.notificationId(
            'habit-$i-${'x' * (i % 40)}', i % 8);
        expect(id, inInclusiveRange(0, 0x7fffffff));
      }
    });
  });
}
