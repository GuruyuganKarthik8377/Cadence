import 'package:flutter_test/flutter_test.dart';
import 'package:cadence/models/habit.dart';
import 'package:cadence/services/insights_service.dart';

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Habit _dailyHabit(List<String> history) => Habit(
      id: 'h1',
      name: 'Test',
      iconOrEmoji: 'star',
      category: 'Fitness',
      habitType: HabitType.build,
      frequency: FrequencyType.daily,
      completionHistory: history,
    );

Habit _habit({
  required FrequencyType frequency,
  required List<String> history,
  List<int> specificDays = const [],
  int timesPerWeek = 1,
  List<int> restDays = const [],
  Set<String> frozen = const {},
}) =>
    Habit(
      id: 'h1',
      name: 'Test',
      iconOrEmoji: 'star',
      category: 'Fitness',
      habitType: HabitType.build,
      frequency: frequency,
      specificDays: specificDays,
      timesPerWeek: timesPerWeek,
      completionHistory: history,
      restDays: restDays,
      frozenDates: frozen,
    );

void main() {
  group('InsightsService week bars', () {
    test('completed today yields a full bar for today', () {
      final today = DateTime.now();
      final service = InsightsService([
        _dailyHabit([_key(today)])
      ]);
      final range = dateRangeFor(InsightRange.week);
      final bars = service.chartData(InsightRange.week, range);

      expect(bars.length, 7);
      final todayBar = bars[today.weekday - 1];
      expect(todayBar.isHighlighted, isTrue);
      expect(todayBar.value, 1.0);
    });

    test('empty history yields zero bars', () {
      final service = InsightsService([_dailyHabit(const [])]);
      final range = dateRangeFor(InsightRange.week);
      final bars = service.chartData(InsightRange.week, range);
      expect(bars.every((b) => b.value == 0), isTrue);
    });
  });

  group('streaks', () {
    test('currentStreak counts consecutive days back from today', () {
      final today = DateTime.now();
      final history = [
        _key(today),
        _key(today.subtract(const Duration(days: 1))),
        _key(today.subtract(const Duration(days: 2))),
        // gap
        _key(today.subtract(const Duration(days: 4))),
      ];
      expect(_dailyHabit(history).currentStreak, 3);
    });

    test('bestStreak finds the longest run anywhere in history', () {
      final today = DateTime.now();
      final history = [
        _key(today),
        // 4-day run last month
        for (var i = 10; i < 14; i++)
          _key(today.subtract(Duration(days: i))),
      ];
      expect(_dailyHabit(history).bestStreak, 4);
    });

    test('an incomplete today does not break a running streak', () {
      final today = DateTime.now();
      final history = [
        for (var i = 1; i <= 3; i++)
          _key(today.subtract(Duration(days: i))),
      ];
      // Today is still in progress — the previous 3 days stand.
      expect(_dailyHabit(history).currentStreak, 3);
    });

    test('specificDays streak skips over unscheduled days', () {
      // Mon/Wed/Fri habit; walk back over the last three scheduled days only.
      final today = DateTime.now();
      final scheduled = <String>[];
      for (var i = 0; i < 21 && scheduled.length < 3; i++) {
        final d = today.subtract(Duration(days: i));
        if (const [0, 2, 4].contains(d.weekday - 1)) scheduled.add(_key(d));
      }
      final habit = _habit(
        frequency: FrequencyType.specificDays,
        specificDays: const [0, 2, 4],
        history: scheduled,
      );
      // Intervening Tue/Thu/weekend days are not misses.
      expect(habit.currentStreak, greaterThanOrEqualTo(3));
    });

    test('specificDays streak still breaks on a missed scheduled day', () {
      final today = DateTime.now();
      final scheduled = <DateTime>[];
      for (var i = 0; i < 28 && scheduled.length < 4; i++) {
        final d = today.subtract(Duration(days: i));
        if (const [0, 2, 4].contains(d.weekday - 1)) scheduled.add(d);
      }
      // Complete the newest two, skip the third, complete the fourth.
      final habit = _habit(
        frequency: FrequencyType.specificDays,
        specificDays: const [0, 2, 4],
        history: [
          _key(scheduled[0]),
          _key(scheduled[1]),
          _key(scheduled[3]),
        ],
      );
      expect(habit.currentStreak, 2);
    });

    test('timesPerWeek streak counts weeks that hit the target', () {
      final today = DateTime.now();
      final monday = today.subtract(Duration(days: today.weekday - 1));
      final history = <String>[];
      // Three full weeks at 3x, starting with last week.
      for (var week = 1; week <= 3; week++) {
        final weekStart = monday.subtract(Duration(days: 7 * week));
        for (var d = 0; d < 3; d++) {
          history.add(_key(weekStart.add(Duration(days: d))));
        }
      }
      final habit = _habit(
        frequency: FrequencyType.timesPerWeek,
        timesPerWeek: 3,
        history: history,
      );
      // The current week is empty but still in progress, so it isn't a miss.
      expect(habit.currentStreak, 3);
      expect(habit.bestStreak, 3);
    });

    test('timesPerWeek streak breaks on a finished week that fell short', () {
      final today = DateTime.now();
      final monday = today.subtract(Duration(days: today.weekday - 1));
      final lastWeek = monday.subtract(const Duration(days: 7));
      final twoWeeksAgo = monday.subtract(const Duration(days: 14));
      final habit = _habit(
        frequency: FrequencyType.timesPerWeek,
        timesPerWeek: 3,
        history: [
          // Last week: only 1 of 3.
          _key(lastWeek),
          // Two weeks ago: a full 3.
          for (var d = 0; d < 3; d++)
            _key(twoWeeksAgo.add(Duration(days: d))),
        ],
      );
      expect(habit.currentStreak, 0);
      expect(habit.bestStreak, 1);
    });

    test('a specificDays habit with no days selected never streaks', () {
      final habit = _habit(
        frequency: FrequencyType.specificDays,
        specificDays: const [],
        history: [_key(DateTime.now())],
      );
      expect(habit.currentStreak, 0);
      expect(habit.bestStreak, 0);
    });
  });

  group('rest days', () {
    test('a rest day is skipped instead of breaking the streak', () {
      final today = DateTime.now();
      // Rest on the weekday that fell two days ago; complete everything else.
      final restWeekday = today.subtract(const Duration(days: 2)).weekday - 1;
      final history = <String>[];
      for (var i = 0; i <= 6; i++) {
        final d = today.subtract(Duration(days: i));
        if (d.weekday - 1 != restWeekday) history.add(_key(d));
      }
      final habit = _habit(
        frequency: FrequencyType.daily,
        history: history,
        restDays: [restWeekday],
      );
      // Six scheduled days completed, the rest day passed over.
      expect(habit.currentStreak, 6);
    });

    test('a rest day drops out of the consistency denominator', () {
      final today = DateTime.now();
      final restWeekday = today.weekday - 1;
      final history = <String>[];
      for (var i = 0; i < 30; i++) {
        final d = today.subtract(Duration(days: i));
        if (d.weekday - 1 != restWeekday) history.add(_key(d));
      }
      final habit = _habit(
        frequency: FrequencyType.daily,
        history: history,
        restDays: [restWeekday],
      );
      // Every non-rest day done — resting must not read as 86%.
      expect(habit.completionRateLast30, 100);
    });

    test('isScheduledOn reports false on a rest day', () {
      final today = DateTime.now();
      final habit = _habit(
        frequency: FrequencyType.daily,
        history: const [],
        restDays: [today.weekday - 1],
      );
      expect(habit.isScheduledOn(today), isFalse);
    });
  });

  group('streak freezes', () {
    test('a frozen miss preserves the streak without extending it', () {
      final today = DateTime.now();
      final missed = today.subtract(const Duration(days: 2));
      final history = [
        for (final i in [1, 3, 4]) _key(today.subtract(Duration(days: i))),
      ];
      final habit = _habit(
        frequency: FrequencyType.daily,
        history: history,
        frozen: {_key(missed)},
      );
      // 3 completed days either side of the freeze; the freeze itself adds 0.
      expect(habit.currentStreak, 3);
    });

    test('without the freeze the same history breaks at the miss', () {
      final today = DateTime.now();
      final history = [
        for (final i in [1, 3, 4]) _key(today.subtract(Duration(days: i))),
      ];
      final habit = _habit(frequency: FrequencyType.daily, history: history);
      expect(habit.currentStreak, 1);
    });

    test('bestStreak carries a run across a frozen day', () {
      final today = DateTime.now();
      final history = [
        for (final i in [1, 3, 4]) _key(today.subtract(Duration(days: i))),
      ];
      final habit = _habit(
        frequency: FrequencyType.daily,
        history: history,
        frozen: {_key(today.subtract(const Duration(days: 2)))},
      );
      expect(habit.bestStreak, 3);
    });

    test('lastMissedDay names the day a freeze would rescue', () {
      final today = DateTime.now();
      final history = [_key(today.subtract(const Duration(days: 2)))];
      final habit = _habit(frequency: FrequencyType.daily, history: history);
      final missed = habit.lastMissedDay;
      expect(missed, isNotNull);
      expect(_key(missed!), _key(today.subtract(const Duration(days: 1))));
    });

    test('lastMissedDay is null while the streak is intact', () {
      final today = DateTime.now();
      final history = [
        for (var i = 1; i <= 3; i++) _key(today.subtract(Duration(days: i))),
      ];
      final habit = _habit(frequency: FrequencyType.daily, history: history);
      expect(habit.lastMissedDay, isNull);
    });

    test('lastMissedDay is null once that day is already frozen', () {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      final habit = _habit(
        frequency: FrequencyType.daily,
        history: const [],
        frozen: {_key(yesterday)},
      );
      expect(habit.lastMissedDay, isNull);
    });

    test('timesPerWeek offers no freeze — a single day is never a miss', () {
      final habit = _habit(
        frequency: FrequencyType.timesPerWeek,
        timesPerWeek: 3,
        history: const [],
      );
      expect(habit.lastMissedDay, isNull);
    });

    test('a rest day is never offered as a missed day', () {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      final habit = _habit(
        frequency: FrequencyType.daily,
        history: [_key(today.subtract(const Duration(days: 2)))],
        restDays: [yesterday.weekday - 1],
      );
      expect(habit.lastMissedDay, isNull);
    });
  });

  group('completionRateLast30', () {
    test('a perfect daily habit reads 100%', () {
      final today = DateTime.now();
      final history = [
        for (var i = 0; i < 30; i++) _key(today.subtract(Duration(days: i))),
      ];
      expect(_dailyHabit(history).completionRateLast30, 100);
    });

    test('a perfect specificDays habit reads 100%, not 43%', () {
      final today = DateTime.now();
      final history = <String>[];
      for (var i = 0; i < 30; i++) {
        final d = today.subtract(Duration(days: i));
        if (const [0, 2, 4].contains(d.weekday - 1)) history.add(_key(d));
      }
      final habit = _habit(
        frequency: FrequencyType.specificDays,
        specificDays: const [0, 2, 4],
        history: history,
      );
      expect(habit.completionRateLast30, 100);
    });

    test('a perfect timesPerWeek habit reads near 100%, not 47%', () {
      final today = DateTime.now();
      final monday = today.subtract(Duration(days: today.weekday - 1));
      final history = <String>[];
      // 3x per week for the five weeks covering the last 30 days.
      for (var week = 0; week < 5; week++) {
        final start = monday.subtract(Duration(days: 7 * week));
        for (var d = 0; d < 3; d++) {
          history.add(_key(start.add(Duration(days: d))));
        }
      }
      final habit = _habit(
        frequency: FrequencyType.timesPerWeek,
        timesPerWeek: 3,
        history: history,
      );
      expect(habit.completionRateLast30, greaterThan(85));
    });

    test('half a daily month reads about 50%', () {
      final today = DateTime.now();
      final history = [
        for (var i = 0; i < 30; i += 2) _key(today.subtract(Duration(days: i))),
      ];
      expect(_dailyHabit(history).completionRateLast30, closeTo(50, 4));
    });

    test('never exceeds 100 when bonus days are logged', () {
      final today = DateTime.now();
      // Mon/Wed/Fri habit completed every single day for a month.
      final history = [
        for (var i = 0; i < 30; i++) _key(today.subtract(Duration(days: i))),
      ];
      final habit = _habit(
        frequency: FrequencyType.specificDays,
        specificDays: const [0, 2, 4],
        history: history,
      );
      expect(habit.completionRateLast30, 100);
    });
  });

  group('bestDayInsight', () {
    test('reports a prompt rather than a day when there is no history', () {
      final service = InsightsService([_dailyHabit(const [])]);
      expect(service.bestDayInsight(), contains('Complete a few habits'));
    });

    test('names the weekday with the highest completion rate', () {
      final today = DateTime.now();
      // Complete only the last four occurrences of today's weekday.
      final history = [
        for (var i = 0; i < 4; i++) _key(today.subtract(Duration(days: i * 7))),
      ];
      final service = InsightsService([_dailyHabit(history)]);
      const names = [
        'Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays',
        'Fridays', 'Saturdays', 'Sundays'
      ];
      expect(service.bestDayInsight(), contains(names[today.weekday - 1]));
    });
  });
}
