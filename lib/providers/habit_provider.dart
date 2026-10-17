import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../models/habit.dart';
import '../services/offline_cache.dart';
import '../services/reminder_service.dart';
import '../services/widget_service.dart';
import 'auth_provider.dart';

final habitsProvider = AsyncNotifierProvider<HabitNotifier, List<Habit>>(
  HabitNotifier.new,
);

/// Archived habits, fetched separately so the main list stays lean.
final archivedHabitsProvider = FutureProvider<List<Habit>>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];
  final rows = await supabase
      .from('habits')
      .select()
      .eq('user_id', userId)
      .eq('is_archived', true)
      .order('updated_at', ascending: false);
  return rows.map((r) => Habit.fromJson(r)).toList();
});

/// Moves one habit and renumbers `sortOrder` to match the new positions.
/// Returns [habits] unchanged (identical) when the move is a no-op or the
/// indices are out of range. Indices are post-removal, as `onReorderItem`
/// reports them.
@visibleForTesting
List<Habit> reorderedHabits(List<Habit> habits, int oldIndex, int newIndex) {
  if (oldIndex == newIndex) return habits;
  if (oldIndex < 0 || oldIndex >= habits.length) return habits;
  if (newIndex < 0 || newIndex >= habits.length) return habits;

  final moved = habits.toList();
  moved.insert(newIndex, moved.removeAt(oldIndex));
  return [
    for (var i = 0; i < moved.length; i++) moved[i].copyWith(sortOrder: i),
  ];
}

String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Fingerprint of everything a reminder depends on. Completing a habit changes
/// the habit list but not this string, so ticking a checkbox doesn't tear down
/// and rebuild every pending notification.
final _reminderSignatureProvider = Provider<String>((ref) {
  final habits = ref.watch(habitsProvider).valueOrNull ?? const <Habit>[];
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  final quiet = [
    profile?.quietHoursStart?.hour,
    profile?.quietHoursStart?.minute,
    profile?.quietHoursEnd?.hour,
    profile?.quietHoursEnd?.minute,
  ].join(',');
  return '$quiet#${habits.where((h) => h.reminderEnabled && h.reminderTime != null).map((h) => [
        h.id,
        h.name,
        h.reminderTime!.hour,
        h.reminderTime!.minute,
        h.repeatReminderDaily,
        h.frequency.name,
        h.specificDays.join(','),
        h.locationName ?? '',
        h.durationValue,
        h.durationUnit,
        h.repeatUntilDone,
        h.repeatIntervalMinutes,
        h.repeatMaxCount,
      ].join(':')).join('|')}';
});

/// Keeps on-device reminders in step with the habit list and the account-level
/// switch. Watch it once from a long-lived widget to keep it alive.
/// Keeps the home screen widget in step with the habit list. Unlike reminders
/// this does follow every completion — a stale checkbox on the home screen is
/// exactly the thing the widget exists to avoid.
final widgetSyncProvider = Provider<void>((ref) {
  final habits = ref.watch(habitsProvider).valueOrNull;
  if (habits == null) return;
  WidgetService.update(habits);
});

final reminderSyncProvider = Provider<void>((ref) {
  // Watched purely as the trigger — this is what decides when we rebuild.
  ref.watch(_reminderSignatureProvider);
  final enabled =
      ref.watch(currentProfileProvider).valueOrNull?.remindersEnabled ?? true;
  // Read, not watch: watching would re-fire on every completion toggle and
  // undo the point of the signature.
  final habits = ref.read(habitsProvider).valueOrNull;
  if (habits == null) return;
  final profile = ref.read(currentProfileProvider).valueOrNull;
  ReminderService.instance.rescheduleAll(
    habits,
    enabled: enabled,
    quietStart: profile?.quietHoursStart,
    quietEnd: profile?.quietHoursEnd,
  );
});

class HabitNotifier extends AsyncNotifier<List<Habit>> {
  @override
  Future<List<Habit>> build() async {
    try {
      // Anything queued while offline goes up before we read, so the fetch
      // reflects those taps instead of overwriting them.
      await _flushPendingToggles();
      final habits = await _fetchHabits();
      unawaited(OfflineCache.saveHabits(habits));
      return habits;
    } catch (e) {
      if (!OfflineCache.isOffline(e)) rethrow;
      final cached = await OfflineCache.loadHabits();
      if (cached == null) rethrow;
      return cached;
    }
  }

  /// Replays offline toggles. Anything the server rejects outright is dropped
  /// rather than retried forever — the queue exists for lost signal, not for
  /// writes that are simply not allowed.
  Future<void> _flushPendingToggles() async {
    final pending = await OfflineCache.pendingToggles();
    if (pending.isEmpty) return;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    for (final toggle in pending) {
      try {
        if (toggle.completed) {
          await supabase.from('habit_completions').upsert(
            {
              'habit_id': toggle.habitId,
              'user_id': userId,
              'completed_on': toggle.date,
            },
            onConflict: 'habit_id,completed_on',
            ignoreDuplicates: true,
          );
        } else {
          await supabase
              .from('habit_completions')
              .delete()
              .eq('habit_id', toggle.habitId)
              .eq('completed_on', toggle.date);
        }
      } catch (e) {
        // Still offline — leave the whole queue for the next attempt.
        if (OfflineCache.isOffline(e)) rethrow;
      }
    }
    await OfflineCache.clearQueue();
  }

  /// Stops (or restores) today's reminders for one habit after it is ticked
  /// off or un-ticked.
  ///
  /// Done as a targeted call rather than by letting reminderSyncProvider
  /// rebuild: its signature deliberately ignores completions so that ticking a
  /// checkbox doesn't tear down and re-arm every pending notification.
  void _syncRemindersFor(Habit habit, {required bool completed}) {
    if (!habit.reminderEnabled || habit.reminderTime == null) return;
    final profile = ref.read(currentProfileProvider).valueOrNull;
    if (profile?.remindersEnabled == false) return;

    if (completed) {
      unawaited(ReminderService.instance.silenceForToday(
        habit,
        quietStart: profile?.quietHoursStart,
        quietEnd: profile?.quietHoursEnd,
      ));
    } else {
      // Un-ticked: today's reminder should come back, so rebuild from scratch.
      final habits = state.valueOrNull;
      if (habits == null) return;
      unawaited(ReminderService.instance.rescheduleAll(
        habits,
        enabled: profile?.remindersEnabled ?? true,
        quietStart: profile?.quietHoursStart,
        quietEnd: profile?.quietHoursEnd,
      ));
    }
  }

  Future<List<Habit>> _fetchHabits() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final habitRows = await supabase
        .from('habits')
        .select()
        .eq('user_id', userId)
        .eq('is_archived', false)
        // created_at breaks ties, so habits from before reordering existed
        // (all sort_order 0) keep the order the user is used to.
        .order('sort_order')
        .order('created_at');

    final habitIds = habitRows.map((r) => r['id'] as String).toList();
    if (habitIds.isEmpty) return [];

    // Completions, freezes and links depend only on habitIds, so they go out
    // together — awaiting them in sequence made a cold load five round trips
    // deep instead of two.
    //
    // ponytail: completions are fetched in full, because bestStreak is
    // all-time. Fine at ~1 year × 10 habits (~3.6k rows); bound the window and
    // keep a stored best_streak column if load time becomes noticeable.
    final related = await Future.wait<List<Map<String, dynamic>>>([
      supabase
          .from('habit_completions')
          .select('id, habit_id, completed_on')
          .inFilter('habit_id', habitIds),
      supabase
          .from('habit_freezes')
          .select('habit_id, frozen_on')
          .inFilter('habit_id', habitIds),
      supabase
          .from('habit_links')
          .select('user_habit_id, friend_habit_id')
          .inFilter('user_habit_id', habitIds)
          .eq('is_active', true),
      // Quantity and note moved off habit_completions in migration 003 —
      // friends can see a linked habit's completions, and that handed them
      // the note text too. Fetched by owner rather than by completion id:
      // only days with extras have a row, so this stays small.
      supabase
          .from('completion_details')
          .select('completion_id, quantity, note')
          .eq('user_id', userId),
    ]);
    final completionRows = related[0];
    final freezeRows = related[1];
    final linkRows = related[2];
    final detailRows = related[3];

    final completionsByHabit = <String, List<String>>{};
    // completion id -> (habit, day), so a details row can be placed without
    // re-querying by thousands of completion ids.
    final slotById = <String, (String, String)>{};
    for (final row in completionRows) {
      final habitId = row['habit_id'] as String;
      final date = row['completed_on'] as String;
      completionsByHabit.putIfAbsent(habitId, () => []).add(date);
      slotById[row['id'] as String] = (habitId, date);
    }

    final detailsByHabit = <String, Map<String, CompletionDetail>>{};
    for (final row in detailRows) {
      // Details for archived habits come back too — those aren't in slotById.
      final slot = slotById[row['completion_id'] as String];
      if (slot == null) continue;
      final quantity = row['quantity'] as int?;
      final note = row['note'] as String?;
      // Only carry days that actually have extras — most rows are plain ticks.
      if (quantity == null && (note == null || note.isEmpty)) continue;
      detailsByHabit.putIfAbsent(slot.$1, () => {})[slot.$2] =
          CompletionDetail(quantity: quantity, note: note);
    }

    final freezesByHabit = <String, Set<String>>{};
    for (final row in freezeRows) {
      freezesByHabit
          .putIfAbsent(row['habit_id'] as String, () => {})
          .add(row['frozen_on'] as String);
    }

    final linkByHabit = <String, String>{}; // user_habit_id -> friend_habit_id
    for (final row in linkRows) {
      linkByHabit[row['user_habit_id'] as String] = row['friend_habit_id'] as String;
    }

    final linkedFriendHabitIds = linkByHabit.values.toList();
    var friendIdByHabit = <String, String>{}; // friend_habit_id -> owning friend's user_id
    if (linkedFriendHabitIds.isNotEmpty) {
      final friendHabitRows = await supabase
          .from('friend_habits')
          .select('id, user_id')
          .inFilter('id', linkedFriendHabitIds);
      for (final row in friendHabitRows) {
        friendIdByHabit[row['id'] as String] = row['user_id'] as String;
      }
    }

    return habitRows.map((row) {
      final id = row['id'] as String;
      final friendHabitId = linkByHabit[id];
      return Habit.fromJson(
        row,
        completionHistory: completionsByHabit[id] ?? const [],
        completionDetails: detailsByHabit[id] ?? const {},
        frozenDates: freezesByHabit[id] ?? const {},
        linkedFriendHabitId: friendHabitId,
        linkedFriendId: friendHabitId != null ? friendIdByHabit[friendHabitId] : null,
      );
    }).toList();
  }

  Future<String> addHabit(Habit habit) async {
    final userId = supabase.auth.currentUser!.id;
    final row = await supabase.from('habits').insert(habit.toJson(userId)).select('id').single();
    ref.invalidateSelf();
    return row['id'] as String;
  }

  Future<void> updateHabit(Habit habit) async {
    final userId = supabase.auth.currentUser!.id;
    await supabase.from('habits').update(habit.toJson(userId)).eq('id', habit.id);
    ref.invalidateSelf();
  }

  Future<void> archiveHabit(String habitId) async {
    await supabase.from('habits').update({'is_archived': true}).eq('id', habitId);
    ref.invalidateSelf();
    ref.invalidate(archivedHabitsProvider);
  }

  Future<void> unarchiveHabit(String habitId) async {
    await supabase.from('habits').update({'is_archived': false}).eq('id', habitId);
    ref.invalidateSelf();
    ref.invalidate(archivedHabitsProvider);
  }

  Future<void> setFavorite(String habitId, bool value) async {
    // Optimistic: flip locally first so the star responds instantly.
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData([
        for (final h in current)
          h.id == habitId ? h.copyWith(isFavorite: value) : h,
      ]);
    }
    try {
      await supabase
          .from('habits')
          .update({'is_favorite': value}).eq('id', habitId);
    } catch (_) {
      ref.invalidateSelf(); // revert on failure
      rethrow;
    }
  }

  /// Moves the habit at [oldIndex] to [newIndex] and persists the new order.
  /// Both indices are post-removal, matching `onReorderItem`.
  Future<void> reorderHabits(int oldIndex, int newIndex) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final renumbered = reorderedHabits(current, oldIndex, newIndex);
    if (identical(renumbered, current)) return;
    state = AsyncData(renumbered);

    try {
      // ponytail: one UPDATE per moved habit. A drag touches at most the span
      // between the two indices, and reordering is rare — swap for a single
      // RPC if a user with 50 habits ever complains.
      await Future.wait([
        for (var i = 0; i < renumbered.length; i++)
          if (current[i].id != renumbered[i].id || current[i].sortOrder != i)
            supabase
                .from('habits')
                .update({'sort_order': i}).eq('id', renumbered[i].id),
      ]);
    } catch (_) {
      ref.invalidateSelf();
      rethrow;
    }
  }

  Future<void> deleteHabit(String habitId) async {
    await supabase.from('habits').delete().eq('id', habitId);
    ref.invalidateSelf();
  }

  Future<void> toggleCompletion(String habitId, DateTime date) async {
    final userId = supabase.auth.currentUser!.id;
    final key = _dateKey(date);
    final previous = state.valueOrNull;

    Habit? habit;
    for (final h in previous ?? const <Habit>[]) {
      if (h.id == habitId) habit = h;
    }
    final wasDone = habit?.completionHistory.contains(key) ?? false;

    // Optimistic: flip locally first so the tap lands instantly. The old path
    // cost a SELECT, a write, then a full refetch (habits + completions +
    // links + friend habits) — six round trips per checkbox tap.
    if (previous != null && habit != null) {
      state = AsyncData([
        for (final h in previous)
          h.id == habitId
              ? h.copyWith(
                  completionHistory: wasDone
                      ? (h.completionHistory.toList()..remove(key))
                      : [...h.completionHistory, key],
                )
              : h,
      ]);
    }

    try {
      if (wasDone) {
        await supabase
            .from('habit_completions')
            .delete()
            .eq('habit_id', habitId)
            .eq('completed_on', key);
      } else {
        await supabase.from('habit_completions').insert({
          'habit_id': habitId,
          'user_id': userId,
          'completed_on': key,
        });
      }
      if (_dateKey(DateTime.now()) == key && habit != null) {
        _syncRemindersFor(habit, completed: !wasDone);
      }
    } catch (e) {
      if (OfflineCache.isOffline(e)) {
        // Keep the optimistic state and replay the tap on reconnect — losing
        // a check-off because the gym has no signal is the whole problem.
        await OfflineCache.queueToggle(PendingToggle(
          habitId: habitId,
          date: key,
          completed: !wasDone,
        ));
        final current = state.valueOrNull;
        if (current != null) unawaited(OfflineCache.saveHabits(current));
        return;
      }
      // The DB can legitimately reject this (the run/walk completion gate),
      // so resync rather than trusting the optimistic state.
      ref.invalidateSelf();
      rethrow;
    }
  }

  /// Spends one streak freeze to protect [date] on [habitId].
  ///
  /// The whole thing — monthly top-up, balance check, freeze insert and
  /// decrement — happens inside use_freeze() with the profile row locked.
  /// It used to be read-then-write from here, which let two quick taps both
  /// see the same balance, and left `freezes_remaining` writable by the
  /// client (so the allowance could simply be reset). Throws a user-readable
  /// [Exception] when the allowance is spent.
  Future<void> useFreeze(String habitId, DateTime date) async {
    try {
      await supabase.rpc('use_freeze', params: {
        'p_habit_id': habitId,
        'p_date': _dateKey(date),
      });
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
    ref.invalidateSelf();
    ref.invalidate(currentProfileProvider);
  }

  /// Claims a bonus streak freeze at the current 7-day milestone.
  /// Returns true when a freeze was awarded, false when there is nothing to
  /// claim (streak < 7, or already claimed at this milestone level).
  Future<bool> earnFreeze(String habitId) async {
    final awarded = await supabase.rpc('award_freeze', params: {'p_habit_id': habitId}) as bool;
    if (awarded) {
      ref.invalidateSelf();
      ref.invalidate(currentProfileProvider);
    }
    return awarded;
  }

  /// Attaches (or clears) a quantity and note on an already-completed day.
  /// Passing null for both clears the extras and leaves the plain tick.
  Future<void> logCompletionDetail(
    String habitId,
    DateTime date, {
    int? quantity,
    String? note,
  }) async {
    final key = _dateKey(date);
    final previous = state.valueOrNull;

    if (previous != null) {
      final detail = CompletionDetail(quantity: quantity, note: note);
      state = AsyncData([
        for (final h in previous)
          if (h.id == habitId)
            h.copyWith(
              completionDetails: {...h.completionDetails}
                ..remove(key)
                ..addAll(detail.isEmpty ? const {} : {key: detail}),
            )
          else
            h,
      ]);
    }

    try {
      // completion_details is keyed on the completion's id, which the habit
      // list doesn't carry, so resolve it first. One extra round trip on an
      // action that happens once a day at most.
      final row = await supabase
          .from('habit_completions')
          .select('id')
          .eq('habit_id', habitId)
          .eq('completed_on', key)
          .maybeSingle();
      if (row == null) {
        ref.invalidateSelf(); // nothing completed that day after all
        return;
      }
      final completionId = row['id'] as String;
      if (quantity == null && (note == null || note.isEmpty)) {
        await supabase
            .from('completion_details')
            .delete()
            .eq('completion_id', completionId);
      } else {
        await supabase.from('completion_details').upsert({
          'completion_id': completionId,
          'user_id': supabase.auth.currentUser!.id,
          'quantity': quantity,
          'note': note,
        }, onConflict: 'completion_id');
      }
    } catch (_) {
      ref.invalidateSelf();
      rethrow;
    }
  }

  /// Marks today complete without toggling — unlike [toggleCompletion], a
  /// second call is a no-op instead of un-completing an already-done habit.
  /// Used when an activity (like finishing a tracked run) should always
  /// result in "done", never "undone".
  Future<void> ensureCompletedToday(String habitId) async {
    final userId = supabase.auth.currentUser!.id;
    final key = _dateKey(DateTime.now());
    Habit? habit;
    for (final h in state.valueOrNull ?? const <Habit>[]) {
      if (h.id == habitId) habit = h;
    }
    try {
      await supabase.from('habit_completions').upsert(
        {'habit_id': habitId, 'user_id': userId, 'completed_on': key},
        onConflict: 'habit_id,completed_on',
        ignoreDuplicates: true,
      );
    } catch (e) {
      if (!OfflineCache.isOffline(e)) rethrow;
      // The home screen widget and the run tracker both land here, and both
      // are places where signal is often missing. Queue rather than lose it.
      await OfflineCache.queueToggle(
        PendingToggle(habitId: habitId, date: key, completed: true),
      );
      final current = state.valueOrNull;
      if (current != null) {
        state = AsyncData([
          for (final h in current)
            if (h.id == habitId && !h.completionHistory.contains(key))
              h.copyWith(completionHistory: [...h.completionHistory, key])
            else
              h,
        ]);
        unawaited(OfflineCache.saveHabits(state.value!));
      }
      return;
    }
    // Ticked off from the widget or a finished run — stop nagging for today.
    if (habit != null) _syncRemindersFor(habit, completed: true);
    ref.invalidateSelf();
  }
}
