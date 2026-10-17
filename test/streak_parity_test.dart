import 'package:flutter_test/flutter_test.dart';

import 'package:cadence/models/habit.dart';

/// Streak parity between the app and the server.
///
/// `Habit.currentStreak` (Dart) and `get_current_streak()` (SQL, defined in
/// supabase/migrations/003_ownership_and_privacy.sql) both have to answer the
/// same question, because the owner sees the Dart number on their own habit
/// while their friends see the SQL number for the same habit on the friends
/// list. They used to disagree: the SQL version counted consecutive calendar
/// days and knew nothing about schedules, rest days or freezes, so a
/// Mon/Wed/Fri habit read 1 to a friend and 12 to its owner.
///
/// Every case below is byte-for-byte the same fixture as a case in the SQL
/// test battery, and expects the same number. If you change the streak rules
/// on one side, change them on the other and update both.
void main() {
  DateTime day(int offset) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day - offset);
  }

  String key(int offset) {
    final d = day(offset);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}'
        '-${d.day.toString().padLeft(2, '0')}';
  }

  /// 0=Mon … 6=Sun, matching both `specific_days` and `rest_days`.
  int weekdayOf(int offset) => day(offset).weekday - 1;

  Habit habit({
    required FrequencyType frequency,
    List<String> completions = const [],
    List<int> specificDays = const [],
    List<int> restDays = const [],
    Set<String> frozen = const {},
    int timesPerWeek = 1,
  }) =>
      Habit(
        id: 'h',
        name: 'Read',
        iconOrEmoji: 'bookOpen',
        category: 'Learning',
        habitType: HabitType.build,
        frequency: frequency,
        specificDays: specificDays,
        restDays: restDays,
        timesPerWeek: timesPerWeek,
        completionHistory: completions,
        frozenDates: frozen,
      );

  test('A — a daily run of 5', () {
    expect(
      habit(
        frequency: FrequencyType.daily,
        completions: [key(0), key(1), key(2), key(3), key(4)],
      ).currentStreak,
      5,
    );
  });

  test('B — today is pending, not a miss', () {
    expect(
      habit(
        frequency: FrequencyType.daily,
        completions: [key(1), key(2), key(3)],
      ).currentStreak,
      3,
    );
  });

  test('C — a miss yesterday ends the run at 1', () {
    expect(
      habit(
        frequency: FrequencyType.daily,
        completions: [key(0), key(2), key(3)],
      ).currentStreak,
      1,
    );
  });

  test('D — unscheduled days are skipped, not counted as misses', () {
    expect(
      habit(
        frequency: FrequencyType.specificDays,
        specificDays: [weekdayOf(0), weekdayOf(2), weekdayOf(4)],
        completions: [key(0), key(2), key(4)],
      ).currentStreak,
      3,
    );
  });

  test('E — a rest day is skipped, not a miss', () {
    expect(
      habit(
        frequency: FrequencyType.daily,
        restDays: [weekdayOf(1)],
        completions: [key(0), key(2)],
      ).currentStreak,
      2,
    );
  });

  test('F — a freeze carries the run without extending it', () {
    expect(
      habit(
        frequency: FrequencyType.daily,
        completions: [key(0), key(2)],
        frozen: {key(1)},
      ).currentStreak,
      2,
    );
  });

  test('G — timesPerWeek counts whole weeks, current week never breaks', () {
    // Monday of this week, then completions two weeks back (2 each) and a
    // short week three back. The current week is empty: short, but pending.
    final today = DateTime.now();
    final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    String fromMonday(int back) {
      final d = DateTime(monday.year, monday.month, monday.day - back);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}'
          '-${d.day.toString().padLeft(2, '0')}';
    }

    expect(
      habit(
        frequency: FrequencyType.timesPerWeek,
        timesPerWeek: 2,
        completions: [
          fromMonday(7), fromMonday(6),
          fromMonday(14), fromMonday(13),
          fromMonday(21),
        ],
      ).currentStreak,
      2,
    );
  });

  test('H — an empty specificDays habit is never scheduled', () {
    expect(
      habit(
        frequency: FrequencyType.specificDays,
        completions: [key(0), key(1), key(2)],
      ).currentStreak,
      0,
    );
  });

  test('I — a habit resting every weekday is never scheduled', () {
    expect(
      habit(
        frequency: FrequencyType.daily,
        restDays: const [0, 1, 2, 3, 4, 5, 6],
        completions: [key(0), key(1), key(2)],
      ).currentStreak,
      0,
    );
  });
}
