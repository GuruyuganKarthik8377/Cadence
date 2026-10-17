import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadence/models/habit.dart';

void main() {
  // The completion set is memoized per instance (it used to be rebuilt on
  // every access, once per iteration inside the streak loops). That is only
  // safe while every write produces a NEW Habit rather than mutating
  // completionHistory in place — these pin that down.
  group('memoized completion set', () {
    Habit habitWith(List<String> history) => Habit(
          id: 'h1',
          name: 'Read',
          iconOrEmoji: 'bookOpen',
          category: 'Learning',
          habitType: HabitType.build,
          frequency: FrequencyType.daily,
          completionHistory: history,
        );

    String key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    test('copyWith produces a habit with its own, updated set', () {
      final today = DateTime.now();
      final before = habitWith([]);
      expect(before.isCompletedOn(today), isFalse); // forces the memo to build

      final after = before.copyWith(completionHistory: [key(today)]);
      expect(after.isCompletedOn(today), isTrue);
      expect(before.isCompletedOn(today), isFalse); // original untouched
    });

    test('repeated reads agree with each other', () {
      final today = DateTime.now();
      final habit = habitWith([key(today)]);
      expect(habit.isCompletedOn(today), isTrue);
      expect(habit.isCompletedOn(today), isTrue);
      expect(habit.currentStreak, greaterThan(0));
      expect(habit.currentStreak, habit.currentStreak);
    });

    test('a streak walk over a long history stays correct', () {
      final today = DateTime(2026, 8, 19);
      final history = [
        for (var i = 0; i < 400; i++)
          key(DateTime(today.year, today.month, today.day - i)),
      ];
      final habit = habitWith(history);
      // Every day present, so the run reaches back the full 400 days.
      expect(habit.bestStreak, 400);
    });
  });

  group('Habit.fromJson / toJson round-trip', () {
    Habit roundTrip(Habit original, String userId) {
      final row = Map<String, dynamic>.from(original.toJson(userId));
      row['id'] = original.id;
      return Habit.fromJson(row);
    }

    test('build habit type', () {
      final habit = Habit(
        id: 'h1',
        name: 'Morning Read',
        iconOrEmoji: 'bookOpen',
        category: 'Learning',
        habitType: HabitType.build,
        frequency: FrequencyType.daily,
      );
      final result = roundTrip(habit, 'u1');
      expect(result.habitType, HabitType.build);
    });

    test('break habit type maps to "break" and back', () {
      final habit = Habit(
        id: 'h2',
        name: 'No Sugar',
        iconOrEmoji: 'apple',
        category: 'Health',
        habitType: HabitType.breakHabit,
        frequency: FrequencyType.daily,
      );
      final json = habit.toJson('u1');
      expect(json['habit_type'], 'break');
      final result = roundTrip(habit, 'u1');
      expect(result.habitType, HabitType.breakHabit);
    });

    test('custom habit type preserves customTypeLabel', () {
      final habit = Habit(
        id: 'h3',
        name: 'Practice Guitar',
        iconOrEmoji: 'music',
        category: 'Hobby',
        habitType: HabitType.custom,
        customTypeLabel: 'Skill',
        frequency: FrequencyType.daily,
      );
      final result = roundTrip(habit, 'u1');
      expect(result.habitType, HabitType.custom);
      expect(result.customTypeLabel, 'Skill');
    });

    test('specificDays frequency maps to "specific_days" and back', () {
      final habit = Habit(
        id: 'h4',
        name: 'Meditation',
        iconOrEmoji: 'wind',
        category: 'Mindfulness',
        habitType: HabitType.build,
        frequency: FrequencyType.specificDays,
        specificDays: const [0, 2, 4],
      );
      final json = habit.toJson('u1');
      expect(json['frequency_type'], 'specific_days');
      final result = roundTrip(habit, 'u1');
      expect(result.frequency, FrequencyType.specificDays);
      expect(result.specificDays, [0, 2, 4]);
    });

    test('timesPerWeek frequency maps to "times_per_week" and back', () {
      final habit = Habit(
        id: 'h5',
        name: 'Gym',
        iconOrEmoji: 'dumbbell',
        category: 'Fitness',
        habitType: HabitType.build,
        frequency: FrequencyType.timesPerWeek,
        timesPerWeek: 4,
      );
      final json = habit.toJson('u1');
      expect(json['frequency_type'], 'times_per_week');
      final result = roundTrip(habit, 'u1');
      expect(result.frequency, FrequencyType.timesPerWeek);
      expect(result.timesPerWeek, 4);
    });

    test('reminderTime serializes to HH:mm:ss and back', () {
      final habit = Habit(
        id: 'h6',
        name: 'Morning Read',
        iconOrEmoji: 'bookOpen',
        category: 'Learning',
        habitType: HabitType.build,
        frequency: FrequencyType.daily,
        reminderEnabled: true,
        reminderTime: const TimeOfDay(hour: 7, minute: 5),
      );
      final json = habit.toJson('u1');
      expect(json['reminder_time'], '07:05:00');
      final result = roundTrip(habit, 'u1');
      expect(result.reminderTime, const TimeOfDay(hour: 7, minute: 5));
    });

    test('null reminderTime stays null', () {
      final habit = Habit(
        id: 'h7',
        name: 'No Reminder',
        iconOrEmoji: 'sun',
        category: 'Health',
        habitType: HabitType.build,
        frequency: FrequencyType.daily,
      );
      final json = habit.toJson('u1');
      expect(json['reminder_time'], null);
      final result = roundTrip(habit, 'u1');
      expect(result.reminderTime, null);
    });

    test('icon_key column maps to iconOrEmoji field', () {
      final habit = Habit(
        id: 'h8',
        name: 'Habit',
        iconOrEmoji: 'dumbbell',
        category: 'Fitness',
        habitType: HabitType.build,
        frequency: FrequencyType.daily,
      );
      final json = habit.toJson('u1');
      expect(json['icon_key'], 'dumbbell');
      final result = roundTrip(habit, 'u1');
      expect(result.iconOrEmoji, 'dumbbell');
    });
  });
}
