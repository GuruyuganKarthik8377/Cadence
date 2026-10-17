import 'package:flutter_test/flutter_test.dart';

import 'package:cadence/models/habit.dart';
import 'package:cadence/services/achievement_service.dart';

void main() {
  String key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';

  /// [days] consecutive completions ending today.
  List<String> run(int days) {
    final now = DateTime.now();
    return [
      for (var i = 0; i < days; i++)
        key(DateTime(now.year, now.month, now.day - i)),
    ];
  }

  Habit habit({String id = 'h1', List<String> completions = const []}) => Habit(
        id: id,
        name: 'Read',
        iconOrEmoji: 'bookOpen',
        category: 'Learning',
        habitType: HabitType.build,
        frequency: FrequencyType.daily,
        completionHistory: completions,
      );

  group('qualifyingAchievements', () {
    test('nothing qualifies with no habits and no friends', () {
      expect(qualifyingAchievements(habits: const [], friendCount: 0), isEmpty);
    });

    test('creating a habit earns the first badge only', () {
      final earned = qualifyingAchievements(
        habits: [habit()],
        friendCount: 0,
      );
      expect(earned, {'first_habit'});
    });

    test('one completion adds first_completion', () {
      final earned = qualifyingAchievements(
        habits: [habit(completions: run(1))],
        friendCount: 0,
      );
      expect(earned, containsAll(['first_habit', 'first_completion']));
      expect(earned, isNot(contains('streak_7')));
    });

    test('streak milestones unlock at their thresholds', () {
      expect(
        qualifyingAchievements(
            habits: [habit(completions: run(7))], friendCount: 0),
        contains('streak_7'),
      );
      expect(
        qualifyingAchievements(
            habits: [habit(completions: run(6))], friendCount: 0),
        isNot(contains('streak_7')),
      );
      expect(
        qualifyingAchievements(
            habits: [habit(completions: run(30))], friendCount: 0),
        contains('streak_30'),
      );
    });

    test('completion milestones count across every habit', () {
      // Two habits, 30 completions each — neither alone reaches 50.
      final habits = [
        habit(id: 'a', completions: run(30)),
        habit(id: 'b', completions: run(30)),
      ];
      expect(qualifyingAchievements(habits: habits, friendCount: 0),
          contains('completions_50'));
    });

    test('five habits earns the variety badge', () {
      final habits = [for (var i = 0; i < 5; i++) habit(id: 'h$i')];
      expect(qualifyingAchievements(habits: habits, friendCount: 0),
          contains('five_habits'));
      expect(
        qualifyingAchievements(
            habits: habits.take(4).toList(), friendCount: 0),
        isNot(contains('five_habits')),
      );
    });

    test('a friend earns the social badge', () {
      expect(qualifyingAchievements(habits: const [], friendCount: 1),
          contains('first_friend'));
    });

    test('every key returned exists in the catalogue', () {
      final earned = qualifyingAchievements(
        habits: [for (var i = 0; i < 5; i++) habit(id: 'h$i', completions: run(100))],
        friendCount: 3,
      );
      final known = achievementCatalogue.map((a) => a.key).toSet();
      expect(earned.difference(known), isEmpty,
          reason: 'a rule awards a key with no catalogue entry to render it');
    });

    test('catalogue keys are unique', () {
      final keys = achievementCatalogue.map((a) => a.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
    });
  });

  group('LifetimeStats', () {
    test('totals sum across habits', () {
      final stats = LifetimeStats.from([
        habit(id: 'a', completions: run(10)),
        habit(id: 'b', completions: run(5)),
      ]);
      expect(stats.totalCompletions, 15);
      expect(stats.bestStreakEver, 10);
      expect(stats.habitCount, 2);
    });

    test('empty input is all zeroes rather than a crash', () {
      final stats = LifetimeStats.from(const []);
      expect(stats.totalCompletions, 0);
      expect(stats.bestStreakEver, 0);
      expect(stats.perfectDays, 0);
    });

    test('a perfect day needs every scheduled habit done', () {
      // Habit A done 3 days, habit B done only today → 1 perfect day.
      final stats = LifetimeStats.from([
        habit(id: 'a', completions: run(3)),
        habit(id: 'b', completions: run(1)),
      ]);
      expect(stats.perfectDays, 1);
    });
  });
}
