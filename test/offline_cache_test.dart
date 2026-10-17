import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cadence/models/habit.dart';
import 'package:cadence/services/offline_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('isOffline', () {
    test('classifies a lost connection as offline', () {
      expect(OfflineCache.isOffline(const SocketException('no route')), isTrue);
      expect(OfflineCache.isOffline(TimeoutException('slow')), isTrue);
      expect(
          OfflineCache.isOffline(
              Exception('Failed host lookup: supabase.co')),
          isTrue);
      expect(OfflineCache.isOffline(Exception('Connection refused')), isTrue);
      expect(OfflineCache.isOffline(Exception('Connection reset by peer')),
          isTrue);
    });

    test('does NOT classify a server rejection as offline', () {
      // These must never be queued for replay — they would fail forever.
      expect(
          OfflineCache.isOffline(
              Exception('PostgrestException: new row violates row-level '
                  'security policy')),
          isFalse);
      expect(
          OfflineCache.isOffline(
              Exception('column habits.sort_order does not exist')),
          isFalse);
      expect(
          OfflineCache.isOffline(
              Exception('run or walk habit requires a run session')),
          isFalse);
      expect(OfflineCache.isOffline(Exception('duplicate key value')), isFalse);
    });
  });

  group('habit cache round-trip', () {
    test('returns null before anything is cached', () async {
      expect(await OfflineCache.loadHabits(), isNull);
    });

    test('preserves the fields the provider assembles from other tables',
        () async {
      final habit = Habit(
        id: 'abc-123',
        name: 'Read',
        iconOrEmoji: 'bookOpen',
        category: 'Learning',
        habitType: HabitType.build,
        frequency: FrequencyType.specificDays,
        specificDays: const [0, 2, 4],
        durationValue: 30,
        durationUnit: 'pages',
        reminderEnabled: true,
        reminderTime: const TimeOfDay(hour: 7, minute: 45),
        completionHistory: const ['2026-01-01', '2026-01-03'],
        completionDetails: const {
          '2026-01-01': CompletionDetail(quantity: 12, note: 'slow'),
        },
        frozenDates: const {'2026-01-02'},
        restDays: const [6],
        sortOrder: 3,
        locationName: 'Library',
        locationLat: 12.9,
        locationLng: 77.6,
      );

      await OfflineCache.saveHabits([habit]);
      final loaded = (await OfflineCache.loadHabits())!.single;

      expect(loaded.id, 'abc-123');
      expect(loaded.name, 'Read');
      expect(loaded.frequency, FrequencyType.specificDays);
      expect(loaded.specificDays, [0, 2, 4]);
      expect(loaded.completionHistory, ['2026-01-01', '2026-01-03']);
      expect(loaded.completionDetails['2026-01-01']?.quantity, 12);
      expect(loaded.completionDetails['2026-01-01']?.note, 'slow');
      expect(loaded.frozenDates, {'2026-01-02'});
      expect(loaded.restDays, [6]);
      expect(loaded.sortOrder, 3);
      expect(loaded.reminderEnabled, isTrue);
      expect(loaded.reminderTime?.hour, 7);
      expect(loaded.reminderTime?.minute, 45);
      expect(loaded.locationName, 'Library');
      expect(loaded.locationLat, 12.9);
    });

    test('a cached streak matches the live one', () async {
      final today = DateTime.now();
      String key(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final habit = Habit(
        id: 'h1',
        name: 'Run',
        iconOrEmoji: 'footprints',
        category: 'Fitness',
        habitType: HabitType.build,
        frequency: FrequencyType.daily,
        completionHistory: [
          for (var i = 0; i < 5; i++) key(today.subtract(Duration(days: i))),
        ],
      );

      await OfflineCache.saveHabits([habit]);
      final loaded = (await OfflineCache.loadHabits())!.single;
      expect(loaded.currentStreak, habit.currentStreak);
      expect(loaded.currentStreak, 5);
    });

    test('clearHabits drops both the list and the queue', () async {
      await OfflineCache.saveHabits([
        Habit(
          id: 'h1',
          name: 'Run',
          iconOrEmoji: 'star',
          category: 'Fitness',
          habitType: HabitType.build,
          frequency: FrequencyType.daily,
        ),
      ]);
      await OfflineCache.queueToggle(const PendingToggle(
          habitId: 'h1', date: '2026-01-01', completed: true));

      await OfflineCache.clearHabits();

      expect(await OfflineCache.loadHabits(), isNull);
      expect(await OfflineCache.pendingToggles(), isEmpty);
    });
  });

  group('pending toggle queue', () {
    test('starts empty', () async {
      expect(await OfflineCache.pendingToggles(), isEmpty);
    });

    test('keeps toggles for different habits and days', () async {
      await OfflineCache.queueToggle(const PendingToggle(
          habitId: 'a', date: '2026-01-01', completed: true));
      await OfflineCache.queueToggle(const PendingToggle(
          habitId: 'b', date: '2026-01-01', completed: true));
      await OfflineCache.queueToggle(const PendingToggle(
          habitId: 'a', date: '2026-01-02', completed: true));
      expect((await OfflineCache.pendingToggles()).length, 3);
    });

    test('collapses repeated toggles of the same habit and day', () async {
      await OfflineCache.queueToggle(const PendingToggle(
          habitId: 'a', date: '2026-01-01', completed: true));
      await OfflineCache.queueToggle(const PendingToggle(
          habitId: 'a', date: '2026-01-01', completed: false));

      final queue = await OfflineCache.pendingToggles();
      // Tapping on then off offline must replay as one final "off", not two
      // opposing writes.
      expect(queue.length, 1);
      expect(queue.single.completed, isFalse);
    });

    test('survives a round-trip through storage', () async {
      await OfflineCache.queueToggle(const PendingToggle(
          habitId: 'h-9', date: '2026-02-14', completed: true));
      final queue = await OfflineCache.pendingToggles();
      expect(queue.single.habitId, 'h-9');
      expect(queue.single.date, '2026-02-14');
      expect(queue.single.completed, isTrue);
    });

    test('clearQueue empties it but keeps the cached habits', () async {
      await OfflineCache.saveHabits([
        Habit(
          id: 'h1',
          name: 'Run',
          iconOrEmoji: 'star',
          category: 'Fitness',
          habitType: HabitType.build,
          frequency: FrequencyType.daily,
        ),
      ]);
      await OfflineCache.queueToggle(const PendingToggle(
          habitId: 'h1', date: '2026-01-01', completed: true));

      await OfflineCache.clearQueue();

      expect(await OfflineCache.pendingToggles(), isEmpty);
      expect(await OfflineCache.loadHabits(), isNotNull);
    });
  });
}
