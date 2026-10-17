import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum HabitType { build, breakHabit, custom }

enum FrequencyType { daily, specificDays, timesPerWeek }

// ---------------------------------------------------------------------------
// Enum <-> Postgres text mapping
// ('break' isn't a valid Dart identifier, and frequency values are
// snake_case in the DB, so `.name` can't be used directly.)
// ---------------------------------------------------------------------------

const Map<HabitType, String> _habitTypeToDb = {
  HabitType.build: 'build',
  HabitType.breakHabit: 'break',
  HabitType.custom: 'custom',
};

const Map<String, HabitType> _dbToHabitType = {
  'build': HabitType.build,
  'break': HabitType.breakHabit,
  'custom': HabitType.custom,
};

const Map<FrequencyType, String> _frequencyToDb = {
  FrequencyType.daily: 'daily',
  FrequencyType.specificDays: 'specific_days',
  FrequencyType.timesPerWeek: 'times_per_week',
};

const Map<String, FrequencyType> _dbToFrequency = {
  'daily': FrequencyType.daily,
  'specific_days': FrequencyType.specificDays,
  'times_per_week': FrequencyType.timesPerWeek,
};

String? _timeOfDayToDb(TimeOfDay? t) {
  if (t == null) return null;
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m:00';
}

TimeOfDay? _timeOfDayFromDb(String? s) {
  if (s == null) return null;
  final parts = s.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

// ---------------------------------------------------------------------------
// Habit model
// ---------------------------------------------------------------------------

/// Optional extras attached to a single completed day. A plain tick has
/// neither, which is what every completion logged before this existed is.
class CompletionDetail {
  /// How much was actually done, in the habit's own [Habit.durationUnit].
  final int? quantity;
  final String? note;

  const CompletionDetail({this.quantity, this.note});

  bool get isEmpty => quantity == null && (note == null || note!.isEmpty);
}

class Habit {
  final String id;
  final String name;
  final String iconOrEmoji;
  final String category; // supports custom strings
  final HabitType habitType;
  final String? customTypeLabel; // filled when habitType == custom
  final FrequencyType frequency;
  final List<int> specificDays; // 0=Mon … 6=Sun, used when frequency==specificDays
  final int timesPerWeek; // used when frequency==timesPerWeek
  final int durationValue;
  final String durationUnit; // 'minutes' | 'times' | 'pages' | custom
  final bool reminderEnabled;
  final TimeOfDay? reminderTime;
  final bool repeatReminderDaily;
  final String? coverImageUrl;
  final bool isFavorite;
  final String? linkedFriendId;
  final String? linkedFriendHabitId;
  /// ISO date strings (yyyy-MM-dd) of days the habit was completed.
  final List<String> completionHistory;
  /// Quantity/note per completed day, keyed by the same yyyy-MM-dd string.
  /// Only holds entries for days that actually have extras, so it's usually
  /// much smaller than [completionHistory].
  final Map<String, CompletionDetail> completionDetails;
  // Location-gated check-in (optional). All three must be non-null to be active.
  final String? locationName;
  final double? locationLat;
  final double? locationLng;
  final int locationRadiusM;
  /// Position in the user's hand-sorted list. Ties break on created_at.
  final int sortOrder;
  /// Weekdays (0=Mon … 6=Sun) deliberately taken off. A rest day is not a
  /// miss — it drops out of the schedule entirely, so it also stops counting
  /// against consistency rates.
  final List<int> restDays;
  /// yyyy-MM-dd strings of days protected by a streak freeze. A frozen day
  /// preserves a streak without extending it.
  final Set<String> frozenDates;

  /// Keep nagging after the reminder time until the habit is ticked off.
  ///
  /// Distinct from [repeatReminderDaily], which is about *which days* get a
  /// reminder at all. This is about follow-ups within a single day.
  final bool repeatUntilDone;

  /// Minutes between follow-ups. Only meaningful when [repeatUntilDone].
  final int repeatIntervalMinutes;

  /// How many follow-ups after the first reminder, 1–5.
  final int repeatMaxCount;

  /// Highest streak count at which a bonus freeze was last awarded for this
  /// habit. The client checks floor(currentStreak/7) > floor(this/7) to decide
  /// whether the "Claim a freeze" milestone is available.
  final int freezeAwardedAtStreak;

  bool get hasLocation => locationLat != null && locationLng != null;

  Habit({
    required this.id,
    required this.name,
    required this.iconOrEmoji,
    required this.category,
    required this.habitType,
    this.customTypeLabel,
    required this.frequency,
    this.specificDays = const [],
    this.timesPerWeek = 1,
    this.durationValue = 0,
    this.durationUnit = 'minutes',
    this.reminderEnabled = false,
    this.reminderTime,
    this.repeatReminderDaily = false,
    this.coverImageUrl,
    this.isFavorite = false,
    this.linkedFriendId,
    this.linkedFriendHabitId,
    this.completionHistory = const [],
    this.completionDetails = const {},
    this.locationName,
    this.locationLat,
    this.locationLng,
    this.locationRadiusM = 200,
    this.sortOrder = 0,
    this.restDays = const [],
    this.frozenDates = const {},
    this.repeatUntilDone = false,
    this.repeatIntervalMinutes = 30,
    this.repeatMaxCount = 3,
    this.freezeAwardedAtStreak = 0,
  });

  Habit copyWith({
    String? id,
    String? name,
    String? iconOrEmoji,
    String? category,
    HabitType? habitType,
    String? customTypeLabel,
    FrequencyType? frequency,
    List<int>? specificDays,
    int? timesPerWeek,
    int? durationValue,
    String? durationUnit,
    bool? reminderEnabled,
    TimeOfDay? reminderTime,
    bool? repeatReminderDaily,
    String? coverImageUrl,
    bool? isFavorite,
    String? linkedFriendId,
    String? linkedFriendHabitId,
    List<String>? completionHistory,
    Map<String, CompletionDetail>? completionDetails,
    String? locationName,
    double? locationLat,
    double? locationLng,
    int? locationRadiusM,
    int? sortOrder,
    List<int>? restDays,
    Set<String>? frozenDates,
    bool? repeatUntilDone,
    int? repeatIntervalMinutes,
    int? repeatMaxCount,
    int? freezeAwardedAtStreak,
    bool clearLocation = false,
  }) {
    return Habit(
      id: id ?? this.id,
      name: name ?? this.name,
      iconOrEmoji: iconOrEmoji ?? this.iconOrEmoji,
      category: category ?? this.category,
      habitType: habitType ?? this.habitType,
      customTypeLabel: customTypeLabel ?? this.customTypeLabel,
      frequency: frequency ?? this.frequency,
      specificDays: specificDays ?? this.specificDays,
      timesPerWeek: timesPerWeek ?? this.timesPerWeek,
      durationValue: durationValue ?? this.durationValue,
      durationUnit: durationUnit ?? this.durationUnit,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderTime: reminderTime ?? this.reminderTime,
      repeatReminderDaily: repeatReminderDaily ?? this.repeatReminderDaily,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      isFavorite: isFavorite ?? this.isFavorite,
      linkedFriendId: linkedFriendId ?? this.linkedFriendId,
      linkedFriendHabitId: linkedFriendHabitId ?? this.linkedFriendHabitId,
      completionHistory: completionHistory ?? this.completionHistory,
      completionDetails: completionDetails ?? this.completionDetails,
      locationName: clearLocation ? null : (locationName ?? this.locationName),
      locationLat: clearLocation ? null : (locationLat ?? this.locationLat),
      locationLng: clearLocation ? null : (locationLng ?? this.locationLng),
      locationRadiusM: locationRadiusM ?? this.locationRadiusM,
      sortOrder: sortOrder ?? this.sortOrder,
      restDays: restDays ?? this.restDays,
      frozenDates: frozenDates ?? this.frozenDates,
      repeatUntilDone: repeatUntilDone ?? this.repeatUntilDone,
      repeatIntervalMinutes:
          repeatIntervalMinutes ?? this.repeatIntervalMinutes,
      repeatMaxCount: repeatMaxCount ?? this.repeatMaxCount,
      freezeAwardedAtStreak:
          freezeAwardedAtStreak ?? this.freezeAwardedAtStreak,
    );
  }

  // ── Supabase (de)serialization ──────────────────────────────────────────
  // `completionHistory`, `linkedFriendId` and `linkedFriendHabitId` are not
  // columns on `habits` — the habit provider populates them from separate
  // `habit_completions` / `habit_links` queries after fetching the row.

  factory Habit.fromJson(
    Map<String, dynamic> json, {
    List<String> completionHistory = const [],
    Map<String, CompletionDetail> completionDetails = const {},
    Set<String> frozenDates = const {},
    String? linkedFriendId,
    String? linkedFriendHabitId,
  }) {
    return Habit(
      id: json['id'] as String,
      name: json['name'] as String,
      iconOrEmoji: json['icon_key'] as String,
      category: json['category'] as String,
      habitType: _dbToHabitType[json['habit_type']] ?? HabitType.build,
      customTypeLabel: json['custom_type_label'] as String?,
      frequency: _dbToFrequency[json['frequency_type']] ?? FrequencyType.daily,
      specificDays: (json['specific_days'] as List?)?.map((e) => e as int).toList() ?? const [],
      timesPerWeek: json['times_per_week'] as int? ?? 1,
      durationValue: json['duration_value'] as int? ?? 0,
      durationUnit: json['duration_unit'] as String? ?? 'minutes',
      reminderEnabled: json['reminder_enabled'] as bool? ?? false,
      reminderTime: _timeOfDayFromDb(json['reminder_time'] as String?),
      repeatReminderDaily: json['repeat_reminder'] as bool? ?? false,
      coverImageUrl: json['cover_image_url'] as String?,
      isFavorite: json['is_favorite'] as bool? ?? false,
      linkedFriendId: linkedFriendId,
      linkedFriendHabitId: linkedFriendHabitId,
      completionHistory: completionHistory,
      completionDetails: completionDetails,
      locationName: json['location_name'] as String?,
      locationLat: (json['location_lat'] as num?)?.toDouble(),
      locationLng: (json['location_lng'] as num?)?.toDouble(),
      locationRadiusM: json['location_radius_m'] as int? ?? 200,
      sortOrder: json['sort_order'] as int? ?? 0,
      restDays:
          (json['rest_days'] as List?)?.map((e) => e as int).toList() ?? const [],
      frozenDates: frozenDates,
      repeatUntilDone: json['repeat_until_done'] as bool? ?? false,
      repeatIntervalMinutes: json['repeat_interval_minutes'] as int? ?? 30,
      repeatMaxCount: json['repeat_max_count'] as int? ?? 3,
      freezeAwardedAtStreak: json['freeze_awarded_at_streak'] as int? ?? 0,
    );
  }

  /// Row payload for insert/update. Excludes `id` (DB-generated) and the
  /// derived fields above.
  Map<String, dynamic> toJson(String userId) => {
        'user_id': userId,
        'name': name,
        'icon_key': iconOrEmoji,
        'category': category,
        'habit_type': _habitTypeToDb[habitType],
        'custom_type_label': customTypeLabel,
        'frequency_type': _frequencyToDb[frequency],
        'specific_days': specificDays,
        'times_per_week': timesPerWeek,
        'duration_value': durationValue,
        'duration_unit': durationUnit,
        'reminder_enabled': reminderEnabled,
        'reminder_time': _timeOfDayToDb(reminderTime),
        'repeat_reminder': repeatReminderDaily,
        'cover_image_url': coverImageUrl,
        'is_favorite': isFavorite,
        'location_name': locationName,
        'location_lat': locationLat,
        'location_lng': locationLng,
        'location_radius_m': locationRadiusM,
        'sort_order': sortOrder,
        'rest_days': restDays,
        'repeat_until_done': repeatUntilDone,
        'repeat_interval_minutes': repeatIntervalMinutes,
        'repeat_max_count': repeatMaxCount,
      };

  // ── Offline cache (de)serialization ────────────────────────────────────
  // Unlike [toJson], this round-trips the whole object including the id and
  // the fields the provider normally assembles from other tables, so a cached
  // list renders identically to a fetched one.

  Map<String, dynamic> toCacheJson() => {
        // user_id is dropped: toJson needs one for writes, but the cache is
        // already per-account (it's cleared on sign-out) and storing a blank
        // one just invites someone to trust it later.
        ...toJson('')..remove('user_id'),
        'id': id,
        'freeze_awarded_at_streak': freezeAwardedAtStreak,
        'completions': completionHistory,
        'frozen': frozenDates.toList(),
        'details': {
          for (final entry in completionDetails.entries)
            entry.key: {
              'quantity': entry.value.quantity,
              'note': entry.value.note,
            },
        },
      };

  factory Habit.fromCacheJson(Map<String, dynamic> json) {
    final rawDetails = (json['details'] as Map?) ?? const {};
    return Habit.fromJson(
      json,
      completionHistory:
          (json['completions'] as List?)?.map((e) => e as String).toList() ??
              const [],
      frozenDates:
          (json['frozen'] as List?)?.map((e) => e as String).toSet() ?? const {},
      completionDetails: {
        for (final entry in rawDetails.entries)
          entry.key as String: CompletionDetail(
            quantity: (entry.value as Map)['quantity'] as int?,
            note: (entry.value as Map)['note'] as String?,
          ),
      },
    );
  }

  // ── Computed stats ─────────────────────────────────────────────────────

  /// Completion dates as a set, built once per instance.
  ///
  /// This was a getter returning `completionHistory.toSet()`, which meant a
  /// fresh O(n) set on every access — including once per iteration inside
  /// [currentStreak]'s 3660-day walk and [bestStreak]'s full-history walk.
  /// Habits are immutable, so building it once is safe.
  late final Set<String> _completed = completionHistory.toSet();

  /// Today's date key.
  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Midnight of [d] — strips any time component so day arithmetic is exact.
  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Day-shifted copy. Built from y/m/d rather than adding a [Duration] so it
  /// stays correct across DST transitions (where a day isn't 24 hours).
  static DateTime _shiftDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  bool isCompletedOn(DateTime date) => _completed.contains(_dateKey(date));

  bool get isCompletedToday => isCompletedOn(DateTime.now());

  /// Whether this habit has a numeric goal worth logging progress against.
  bool get hasGoal => durationValue > 0;

  CompletionDetail? detailOn(DateTime date) =>
      completionDetails[_dateKey(date)];

  int? quantityOn(DateTime date) => detailOn(date)?.quantity;

  String? noteOn(DateTime date) {
    final note = detailOn(date)?.note;
    return (note == null || note.isEmpty) ? null : note;
  }

  /// Total logged quantity over the last [days] days. Days completed without a
  /// quantity count as a full goal, since a plain tick means "I did it".
  int loggedQuantityLast(int days) {
    final today = _midnight(DateTime.now());
    var total = 0;
    for (var i = 0; i < days; i++) {
      final key = _dateKey(_shiftDays(today, -i));
      if (!_completed.contains(key)) continue;
      total += completionDetails[key]?.quantity ?? durationValue;
    }
    return total;
  }

  /// Whether this habit is due on [date] under its frequency rule.
  /// `timesPerWeek` habits have no fixed days, so every day counts as eligible.
  ///
  /// Rest days are subtracted here rather than in each caller, so they drop
  /// out of streaks, completion rates and insight denominators together.
  bool isScheduledOn(DateTime date) {
    if (restDays.contains(date.weekday - 1)) return false;
    switch (frequency) {
      case FrequencyType.daily:
        return true;
      case FrequencyType.specificDays:
        return specificDays.contains(date.weekday - 1);
      case FrequencyType.timesPerWeek:
        return true;
    }
  }

  bool isFrozenOn(DateTime date) => frozenDates.contains(_dateKey(date));

  /// The most recent scheduled day that was neither completed nor already
  /// frozen — i.e. the day a freeze would rescue. Null when the streak is
  /// intact. Today is excluded: it's still in progress.
  DateTime? get lastMissedDay {
    // timesPerWeek streaks are counted in weeks, so no single day is ever a
    // miss and there is nothing for a freeze to rescue.
    if (frequency == FrequencyType.timesPerWeek) return null;
    if (frequency == FrequencyType.specificDays && specificDays.isEmpty) {
      return null;
    }
    var day = _shiftDays(_midnight(DateTime.now()), -1);
    // A season's worth of lookback; beyond that the streak is long gone.
    for (int guard = 0; guard < 120; guard++) {
      if (isScheduledOn(day)) {
        final key = _dateKey(day);
        if (frozenDates.contains(key)) return null; // already protected
        if (!_completed.contains(key)) return day;
        return null; // the most recent scheduled day was done
      }
      day = _shiftDays(day, -1);
    }
    return null;
  }

  /// Completion counts per ISO week, oldest first. The final entry is the
  /// current (still in-progress) week. Empty when there's no history.
  List<int> _weeklyCounts() {
    if (_completed.isEmpty) return const [];
    final dates = _completed.map(DateTime.parse).toList()..sort();
    final today = _midnight(DateTime.now());
    final thisMonday = _shiftDays(today, -(today.weekday - 1));
    var monday = _shiftDays(dates.first, -(dates.first.weekday - 1));

    final counts = <int>[];
    while (!monday.isAfter(thisMonday)) {
      final next = _shiftDays(monday, 7);
      counts.add(dates
          .where((d) => !d.isBefore(monday) && d.isBefore(next))
          .length);
      monday = next;
    }
    return counts;
  }

  /// Current streak, measured against the habit's own schedule.
  ///
  /// - `daily` / `specificDays` — consecutive *scheduled* days. Unscheduled
  ///   days are skipped over rather than breaking the run, so a Mon/Wed/Fri
  ///   habit isn't punished for "missing" Tuesday.
  /// - `timesPerWeek` — consecutive weeks that hit the target.
  ///
  /// Today (or the current week) never breaks a streak: it's still in progress,
  /// so it either extends the run or is passed over.
  int get currentStreak {
    if (frequency == FrequencyType.timesPerWeek) {
      final counts = _weeklyCounts();
      int streak = 0;
      for (int i = counts.length - 1; i >= 0; i--) {
        if (counts[i] >= timesPerWeek) {
          streak++;
        } else if (i != counts.length - 1) {
          break; // a finished week fell short — the run ends there
        }
      }
      return streak;
    }

    if (frequency == FrequencyType.specificDays && specificDays.isEmpty) {
      return 0; // nothing is ever scheduled
    }

    var day = _midnight(DateTime.now());
    // An incomplete today is "pending", not a miss — start from yesterday.
    if (!_completed.contains(_dateKey(day))) day = _shiftDays(day, -1);

    int streak = 0;
    // Bounded so an all-unscheduled configuration can't spin forever.
    for (int guard = 0; guard < 3660; guard++) {
      if (isScheduledOn(day)) {
        final key = _dateKey(day);
        if (!_completed.contains(key)) {
          // A freeze preserves the run without extending it; anything else
          // ends it.
          if (!frozenDates.contains(key)) break;
        } else {
          streak++;
        }
      }
      day = _shiftDays(day, -1);
    }
    return streak;
  }

  /// Longest streak ever achieved, using the same schedule rules as
  /// [currentStreak] so the two can never disagree.
  int get bestStreak {
    if (_completed.isEmpty) return 0;

    if (frequency == FrequencyType.timesPerWeek) {
      int best = 0, run = 0;
      for (final count in _weeklyCounts()) {
        run = count >= timesPerWeek ? run + 1 : 0;
        if (run > best) best = run;
      }
      return best;
    }

    if (frequency == FrequencyType.specificDays && specificDays.isEmpty) {
      return 0;
    }

    final first = _completed.map(DateTime.parse).reduce(
        (a, b) => a.isBefore(b) ? a : b);
    final today = _midnight(DateTime.now());

    int best = 0, run = 0;
    for (var day = _midnight(first);
        !day.isAfter(today);
        day = _shiftDays(day, 1)) {
      if (!isScheduledOn(day)) continue;
      final key = _dateKey(day);
      if (_completed.contains(key)) {
        run++;
      } else if (frozenDates.contains(key)) {
        continue; // protected — carry the run across without extending it
      } else {
        run = 0;
      }
      if (run > best) best = run;
    }
    return best;
  }

  /// Completion rate over the last 30 days (0–100), measured against what the
  /// schedule actually asked for. Dividing by a flat 30 capped a perfect
  /// Mon/Wed/Fri habit at 43% and a perfect 3×/week habit at 47%.
  int get completionRateLast30 {
    final today = _midnight(DateTime.now());
    int done = 0;
    for (int i = 0; i < 30; i++) {
      if (_completed.contains(_dateKey(_shiftDays(today, -i)))) done++;
    }

    final double expected;
    if (frequency == FrequencyType.timesPerWeek) {
      expected = timesPerWeek * 30 / 7;
    } else {
      int days = 0;
      for (int i = 0; i < 30; i++) {
        if (isScheduledOn(_shiftDays(today, -i))) days++;
      }
      expected = days.toDouble();
    }
    if (expected <= 0) return 0;
    // Extra sessions on unscheduled days still count, so clamp the overshoot.
    return ((done / expected) * 100).round().clamp(0, 100);
  }
}

// ---------------------------------------------------------------------------
// Icon key → Lucide IconData lookup
// Replaces emoji usage throughout the app for consistent rendering on all
// Android devices (no OS/keyboard-dependent emoji variation).
// ---------------------------------------------------------------------------

/// Maps a string icon key to the corresponding Lucide [IconData].
/// Falls back to [LucideIcons.sparkles] for unrecognised keys.
IconData habitIconData(String key) {
  const map = <String, IconData>{
    'bookOpen': LucideIcons.bookOpen,
    'wind': LucideIcons.wind,
    'dumbbell': LucideIcons.dumbbell,
    'flame': LucideIcons.flame,
    'moon': LucideIcons.moon,
    'sun': LucideIcons.sun,
    'coffee': LucideIcons.coffee,
    'music': LucideIcons.music,
    'code': LucideIcons.code,
    'palette': LucideIcons.palette,
    'heart': LucideIcons.heart,
    'target': LucideIcons.target,
    'brain': LucideIcons.brain,
    'footprints': LucideIcons.footprints,
    'bike': LucideIcons.bike,
    'apple': LucideIcons.apple,
    'droplet': LucideIcons.droplet,
    'penLine': LucideIcons.penLine,
    'camera': LucideIcons.camera,
    'briefcase': LucideIcons.briefcase,
    'graduationCap': LucideIcons.graduationCap,
    'leaf': LucideIcons.leaf,
    'zap': LucideIcons.zap,
    'star': LucideIcons.star,
    'bed': LucideIcons.bed,
    'shoppingBag': LucideIcons.shoppingBag,
    'clock': LucideIcons.clock,
    'trophy': LucideIcons.trophy,
    'smile': LucideIcons.smile,
    'activity': LucideIcons.activity,
  };
  return map[key] ?? LucideIcons.sparkles;
}

// ---------------------------------------------------------------------------
// Preset cover image URLs
// ---------------------------------------------------------------------------

const List<String> presetCoverImages = [
  'https://images.unsplash.com/photo-1544947950-fa07a98d237f?ixlib=rb-1.2.1&auto=format&fit=crop&w=400&q=80',
  'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?ixlib=rb-1.2.1&auto=format&fit=crop&w=400&q=80',
  'https://images.unsplash.com/photo-1508672019048-805c876b67e2?ixlib=rb-1.2.1&auto=format&fit=crop&w=400&q=80',
  'https://images.unsplash.com/photo-1515378791036-0648a3ef77b2?ixlib=rb-1.2.1&auto=format&fit=crop&w=400&q=80',
  'https://images.unsplash.com/photo-1476480862126-209bfaa8edc8?ixlib=rb-1.2.1&auto=format&fit=crop&w=400&q=80',
  'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?ixlib=rb-1.2.1&auto=format&fit=crop&w=400&q=80',
];

/// The cover image to show for a habit. Uses the habit's own cover when set,
/// otherwise a stable pick from [presetCoverImages] (keyed on the habit id so
/// the same habit always shows the same image). Only ever returns images the
/// app already ships — never fetches anything new.
String habitCoverImageFor(String? coverImageUrl, String key) {
  if (coverImageUrl != null && coverImageUrl.isNotEmpty) return coverImageUrl;
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return presetCoverImages[hash % presetCoverImages.length];
}

/// Habits considered "running or walking" for accelerometer verification —
/// their name or category names run/walk as a whole word (so "running",
/// "walking", "walker" all match, but "Grocery" or "Sunbathe" don't).
///
/// This mirrors the SQL function `is_run_or_walk_habit` in schema.sql,
/// which is the actual source of truth: the database rejects any completion
/// insert for these habits that isn't backed by a same-day run_sessions row
/// with steps > 0, regardless of what the client sends. This Dart copy only
/// drives UI (showing the Start Run button, disabling the manual toggle) —
/// keep both definitions in sync if the matching rule ever changes.
bool isRunOrWalkHabit(Habit habit) {
  final pattern = RegExp(r'\b(run|walk)', caseSensitive: false);
  return pattern.hasMatch(habit.name) || pattern.hasMatch(habit.category);
}

// ---------------------------------------------------------------------------
// Mock data has been removed — habits now come from HabitNotifier
// (see lib/providers/habit_provider.dart), which fetches real rows from
// Supabase.
// ---------------------------------------------------------------------------
