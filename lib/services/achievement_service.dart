import '../models/habit.dart';

/// One earnable milestone.
///
/// The catalogue lives in the app rather than the database: every rule needs
/// the same habit data the app already holds in memory, and re-deriving
/// streaks in SQL to award a badge would mean maintaining the streak rules
/// twice. The `achievements` table only records *that* a key unlocked and on
/// what date.
class Achievement {
  /// Stable id stored in `achievements.key`. Never reuse or repurpose one —
  /// a retired badge should keep rendering for whoever already earned it.
  final String key;
  final String title;
  final String description;
  final String iconKey;

  const Achievement({
    required this.key,
    required this.title,
    required this.description,
    required this.iconKey,
  });
}

/// An [Achievement] plus whether (and when) the signed-in user has it.
class EarnedAchievement {
  final Achievement achievement;
  final DateTime? unlockedOn;

  const EarnedAchievement({required this.achievement, this.unlockedOn});

  bool get isUnlocked => unlockedOn != null;
}

/// Milestones, roughly easiest first — the profile renders them in this order.
const List<Achievement> achievementCatalogue = [
  Achievement(
    key: 'first_habit',
    title: 'First Step',
    description: 'Create your first habit',
    iconKey: 'sparkles',
  ),
  Achievement(
    key: 'first_completion',
    title: 'Off the Mark',
    description: 'Complete a habit for the first time',
    iconKey: 'check',
  ),
  Achievement(
    key: 'streak_7',
    title: 'One Week',
    description: 'Hold a 7-day streak',
    iconKey: 'flame',
  ),
  Achievement(
    key: 'streak_30',
    title: 'One Month',
    description: 'Hold a 30-day streak',
    iconKey: 'trophy',
  ),
  Achievement(
    key: 'streak_100',
    title: 'Centurion',
    description: 'Hold a 100-day streak',
    iconKey: 'star',
  ),
  Achievement(
    key: 'completions_50',
    title: 'Fifty Done',
    description: 'Log 50 completions',
    iconKey: 'target',
  ),
  Achievement(
    key: 'completions_250',
    title: 'Regular',
    description: 'Log 250 completions',
    iconKey: 'activity',
  ),
  Achievement(
    key: 'completions_1000',
    title: 'Devoted',
    description: 'Log 1000 completions',
    iconKey: 'zap',
  ),
  Achievement(
    key: 'five_habits',
    title: 'Well Rounded',
    description: 'Keep five habits at once',
    iconKey: 'list',
  ),
  Achievement(
    key: 'first_friend',
    title: 'Accountable',
    description: 'Connect with a friend',
    iconKey: 'heart',
  ),
];

/// Lifetime totals shown on the profile. All derived from data already
/// loaded — nothing here costs a round trip.
class LifetimeStats {
  final int totalCompletions;
  final int bestStreakEver;
  final int currentBestStreak;
  final int habitCount;
  final int perfectDays;

  const LifetimeStats({
    required this.totalCompletions,
    required this.bestStreakEver,
    required this.currentBestStreak,
    required this.habitCount,
    required this.perfectDays,
  });

  static LifetimeStats from(List<Habit> habits) {
    var total = 0;
    var best = 0;
    var current = 0;
    for (final habit in habits) {
      total += habit.completionHistory.length;
      if (habit.bestStreak > best) best = habit.bestStreak;
      if (habit.currentStreak > current) current = habit.currentStreak;
    }
    return LifetimeStats(
      totalCompletions: total,
      bestStreakEver: best,
      currentBestStreak: current,
      habitCount: habits.length,
      perfectDays: _perfectDays(habits),
    );
  }

  /// Days where every habit that was scheduled actually got done.
  ///
  /// Only counts days that had at least one scheduled habit, so an empty
  /// early history doesn't inflate the number.
  static int _perfectDays(List<Habit> habits) {
    if (habits.isEmpty) return 0;

    final allDates = <String>{};
    for (final habit in habits) {
      allDates.addAll(habit.completionHistory);
    }
    if (allDates.isEmpty) return 0;

    var perfect = 0;
    for (final key in allDates) {
      final day = DateTime.tryParse(key);
      if (day == null) continue;
      var scheduled = 0;
      var done = 0;
      for (final habit in habits) {
        if (!habit.isScheduledOn(day)) continue;
        scheduled++;
        if (habit.isCompletedOn(day)) done++;
      }
      if (scheduled > 0 && scheduled == done) perfect++;
    }
    return perfect;
  }
}

/// Which milestone keys the given state qualifies for, right now.
///
/// Pure and synchronous so the rules are testable without a database. The
/// caller diffs this against what's already stored and inserts the difference.
Set<String> qualifyingAchievements({
  required List<Habit> habits,
  required int friendCount,
}) {
  final stats = LifetimeStats.from(habits);
  return {
    if (habits.isNotEmpty) 'first_habit',
    if (stats.totalCompletions >= 1) 'first_completion',
    if (stats.bestStreakEver >= 7) 'streak_7',
    if (stats.bestStreakEver >= 30) 'streak_30',
    if (stats.bestStreakEver >= 100) 'streak_100',
    if (stats.totalCompletions >= 50) 'completions_50',
    if (stats.totalCompletions >= 250) 'completions_250',
    if (stats.totalCompletions >= 1000) 'completions_1000',
    if (habits.length >= 5) 'five_habits',
    if (friendCount >= 1) 'first_friend',
  };
}
