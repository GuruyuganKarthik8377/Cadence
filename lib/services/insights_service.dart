import '../models/habit.dart';

// ---------------------------------------------------------------------------
// Date utility
// ---------------------------------------------------------------------------

String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Normalises a DateTime to midnight so time components don't affect equality.
DateTime _date(DateTime d) => DateTime(d.year, d.month, d.day);

// ---------------------------------------------------------------------------
// Date range helpers
// ---------------------------------------------------------------------------

enum InsightRange { week, month, year }

/// Returns the inclusive [start, end] for each range relative to today.
DateRange dateRangeFor(InsightRange range) {
  final today = _date(DateTime.now());
  switch (range) {
    case InsightRange.week:
      // Monday of the current ISO week
      final monday = today.subtract(Duration(days: today.weekday - 1));
      return DateRange(monday, today);
    case InsightRange.month:
      final start = DateTime(today.year, today.month, 1);
      return DateRange(start, today);
    case InsightRange.year:
      final start = DateTime(today.year, 1, 1);
      return DateRange(start, today);
  }
}

class DateRange {
  final DateTime start;
  final DateTime end;
  const DateRange(this.start, this.end);

  int get daysCount => end.difference(start).inDays + 1;

  List<DateTime> get days {
    return List.generate(
      daysCount,
      (i) => start.add(Duration(days: i)),
    );
  }
}

// ---------------------------------------------------------------------------
// InsightsService — all aggregation calculations
// ---------------------------------------------------------------------------

class InsightsService {
  final List<Habit> habits;

  const InsightsService(this.habits);

  bool get hasAnyHistory =>
      habits.any((h) => h.completionHistory.isNotEmpty);

  // ── Overview stats ─────────────────────────────────────────────────────

  /// Overall completion rate for the given range.
  /// = completed habit-days / total scheduled habit-days
  double overallConsistency(DateRange range) {
    int total = 0;
    int completed = 0;
    for (final habit in habits) {
      for (final day in range.days) {
        if (habit.isScheduledOn(day)) {
          total++;
          if (habit.isCompletedOn(day)) completed++;
        }
      }
    }
    if (total == 0) return 0;
    return completed / total;
  }

  /// Total completions within the range.
  int totalCompletions(DateRange range) {
    int count = 0;
    for (final habit in habits) {
      for (final day in range.days) {
        if (habit.isCompletedOn(day)) count++;
      }
    }
    return count;
  }

  int get activeHabitsCount => habits.length;

  // ── Bar chart data ──────────────────────────────────────────────────────

  /// Returns a list of (label, fraction 0–1) for the consistency bar chart.
  /// Week  → 7 bars, Mon–Sun labels
  /// Month → 4–5 bars, "Week N" labels
  /// Year  → 12 bars, month abbreviation labels
  List<BarPoint> chartData(InsightRange insightRange, DateRange range) {
    switch (insightRange) {
      case InsightRange.week:
        return _weekBars(range);
      case InsightRange.month:
        return _monthBars(range);
      case InsightRange.year:
        return _yearBars(range);
    }
  }

  List<BarPoint> _weekBars(DateRange range) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final today = _date(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return List.generate(7, (i) {
      final day = monday.add(Duration(days: i));
      return BarPoint(
        label: labels[i],
        value: _fractionForDay(day),
        isHighlighted: _dateKey(day) == _dateKey(today),
      );
    });
  }

  List<BarPoint> _monthBars(DateRange range) {
    // Group by ISO week
    final today = _date(DateTime.now());
    final startOfMonth = range.start;
    final weeks = <int, List<DateTime>>{};
    var d = startOfMonth;
    while (!d.isAfter(range.end)) {
      final weekNum = _isoWeekOfMonth(d, startOfMonth);
      weeks.putIfAbsent(weekNum, () => []).add(d);
      d = d.add(const Duration(days: 1));
    }
    final sorted = weeks.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return sorted.map((entry) {
      final days = entry.value;
      final frac = _fractionForRange(days);
      final isCurrentWeek = days.any((day) => _dateKey(day) == _dateKey(today));

      return BarPoint(
        label: 'W${entry.key}',
        value: frac,
        isHighlighted: isCurrentWeek,
      );
    }).toList();
  }

  List<BarPoint> _yearBars(DateRange range) {
    const monthAbbr = [
      'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'
    ];
    final today = _date(DateTime.now());
    return List.generate(12, (i) {
      final month = i + 1;
      final year = range.start.year;
      final daysInMonth = DateTime(year, month + 1, 0).day;
      final days = List.generate(
          daysInMonth, (d) => DateTime(year, month, d + 1));
      final validDays =
          days.where((day) => !day.isAfter(today)).toList();
      final frac = _fractionForRange(validDays);
      return BarPoint(
        label: monthAbbr[i],
        value: frac,
        isHighlighted: month == today.month && year == today.year,
      );
    });
  }

  double _fractionForDay(DateTime day) {
    int scheduled = 0;
    int done = 0;
    for (final h in habits) {
      if (h.isScheduledOn(day)) {
        scheduled++;
        if (h.isCompletedOn(day)) done++;
      }
    }
    if (scheduled == 0) return 0;
    return done / scheduled;
  }

  double _fractionForRange(List<DateTime> days) {
    if (days.isEmpty) return 0;
    final sum = days.fold(0.0, (s, d) => s + _fractionForDay(d));
    return sum / days.length;
  }

  int _isoWeekOfMonth(DateTime day, DateTime monthStart) {
    return ((day.day - 1) ~/ 7) + 1;
  }

  // ── Streak data ─────────────────────────────────────────────────────────

  /// Habits sorted by longest active streak, descending.
  List<HabitStreakInfo> streaksSorted() {
    final infos = habits
        .map((h) => HabitStreakInfo(habit: h, streak: h.currentStreak))
        .toList()
      ..sort((a, b) => b.streak.compareTo(a.streak));
    return infos;
  }

  // ── Habit breakdown ─────────────────────────────────────────────────────

  /// Habits sorted by completion rate (selected range), descending.
  List<HabitBreakdown> breakdownSorted(DateRange range) {
    final list = habits.map((h) {
      int total = 0;
      int done = 0;
      for (final day in range.days) {
        if (h.isScheduledOn(day)) {
          total++;
          if (h.isCompletedOn(day)) done++;
        }
      }
      final rate = total == 0 ? 0.0 : done / total;
      return HabitBreakdown(habit: h, rate: rate);
    }).toList()
      ..sort((a, b) => b.rate.compareTo(a.rate));
    return list;
  }

  // ── Best day insight ────────────────────────────────────────────────────

  /// Returns a rule-based insight string derived from completionHistory.
  ///
  /// Completions and scheduled days are both counted over the same trailing
  /// 90-day window — mixing all-time completions with a 90-day denominator
  /// (as an earlier version did) produced rates above 100%.
  String bestDayInsight() {
    final counts = List.filled(7, 0);
    final scheduled = List.filled(7, 0);
    final today = _date(DateTime.now());

    for (int i = 0; i < 90; i++) {
      final day = today.subtract(Duration(days: i));
      final idx = day.weekday - 1;
      for (final h in habits) {
        if (!h.isScheduledOn(day)) continue;
        scheduled[idx]++;
        if (h.isCompletedOn(day)) counts[idx]++;
      }
    }

    int bestIdx = -1;
    double bestRate = 0;
    for (int i = 0; i < 7; i++) {
      if (scheduled[i] == 0) continue;
      final rate = counts[i] / scheduled[i];
      if (rate > bestRate) {
        bestRate = rate;
        bestIdx = i;
      }
    }

    if (bestIdx == -1) {
      return 'Complete a few habits to see which days suit you best.';
    }

    const dayNames = [
      'Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays',
      'Fridays', 'Saturdays', 'Sundays'
    ];
    return 'You\'re most consistent on ${dayNames[bestIdx]}.';
  }

  // ── Period-over-period trend ────────────────────────────────────────────

  /// Change in consistency versus the immediately preceding period of equal
  /// length, in percentage points (+12 = twelve points better than last time).
  /// Null when there's no scheduled history to compare against.
  int? consistencyDelta(DateRange range) {
    final days = range.daysCount;
    final previous = DateRange(
      range.start.subtract(Duration(days: days)),
      range.start.subtract(const Duration(days: 1)),
    );
    if (!_hasScheduledDays(previous)) return null;
    final delta = overallConsistency(range) - overallConsistency(previous);
    return (delta * 100).round();
  }

  bool _hasScheduledDays(DateRange range) => habits.any(
      (h) => range.days.any((d) => h.isScheduledOn(d)));

  // ── Category breakdown ──────────────────────────────────────────────────

  /// Returns category → fraction 0–1 for last 30 days.
  List<CategoryBreakdown> categoryBreakdown() {
    final today = _date(DateTime.now());
    final range = DateRange(
      today.subtract(const Duration(days: 29)),
      today,
    );

    final catTotals = <String, int>{};
    final catDone = <String, int>{};

    for (final h in habits) {
      for (final day in range.days) {
        if (h.isScheduledOn(day)) {
          catTotals[h.category] = (catTotals[h.category] ?? 0) + 1;
          if (h.isCompletedOn(day)) {
            catDone[h.category] = (catDone[h.category] ?? 0) + 1;
          }
        }
      }
    }

    final result = catTotals.entries.map((e) {
      final rate = (catDone[e.key] ?? 0) / e.value;
      return CategoryBreakdown(category: e.key, rate: rate, total: e.value);
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return result;
  }

}

// ---------------------------------------------------------------------------
// Data transfer objects
// ---------------------------------------------------------------------------

class BarPoint {
  final String label;
  final double value; // 0–1
  final bool isHighlighted;
  const BarPoint({
    required this.label,
    required this.value,
    required this.isHighlighted,
  });
}

class HabitStreakInfo {
  final Habit habit;
  final int streak;
  const HabitStreakInfo({required this.habit, required this.streak});
}

class HabitBreakdown {
  final Habit habit;
  final double rate; // 0–1
  const HabitBreakdown({required this.habit, required this.rate});
}

class CategoryBreakdown {
  final String category;
  final double rate; // 0–1 completion rate
  final int total;
  const CategoryBreakdown({
    required this.category,
    required this.rate,
    required this.total,
  });
}
