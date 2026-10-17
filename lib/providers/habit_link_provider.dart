import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/habit.dart';
import '../models/habit_link.dart';
import 'auth_provider.dart';

final habitLinksProvider = AsyncNotifierProvider<HabitLinkNotifier, List<HabitLink>>(
  HabitLinkNotifier.new,
);

/// A friend's non-archived habits, for the "link a habit" picker.
/// `Habit.fromJson` is reused here purely for its icon/name fields —
/// completionHistory and linkedFriend* stay empty, which is fine since
/// this list is only used to pick a habit to link, never displayed as a
/// full habit card.
///
/// Reads the `friend_habits` view, not `habits`. The view exposes only the
/// columns a friend is allowed to see — in particular it has no location
/// columns, which a bare select() on the base table used to hand over.
final friendHabitsProvider = FutureProvider.family<List<Habit>, String>((ref, friendUserId) async {
  final rows = await supabase
      .from('friend_habits')
      .select()
      .eq('user_id', friendUserId)
      .eq('is_archived', false)
      .order('created_at');
  return rows.map((r) => Habit.fromJson(r)).toList();
});

class HabitLinkNotifier extends AsyncNotifier<List<HabitLink>> {
  @override
  Future<List<HabitLink>> build() => _fetch();

  Future<List<HabitLink>> _fetch() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final myHabitRows = await supabase.from('habits').select('id').eq('user_id', userId);
    final myHabitIds = myHabitRows.map((r) => r['id'] as String).toList();
    if (myHabitIds.isEmpty) return [];

    final linkRows = await supabase.from('habit_links').select().inFilter('user_habit_id', myHabitIds);
    if (linkRows.isEmpty) return [];

    final habitIds = {
      for (final r in linkRows) ...[r['user_habit_id'] as String, r['friend_habit_id'] as String],
    }.toList();

    final habitRows = await supabase
        .from('friend_habits')
        .select('id, name, icon_key, user_id')
        .inFilter('id', habitIds);
    final habitsById = {for (final h in habitRows) h['id'] as String: h};

    // One round trip for every streak this screen needs — get_current_streak
    // is security definer and already allows "own habit or accepted friend's
    // habit", so both sides of every pair can go through the same RPC call.
    final streakRows = await supabase
        .rpc('get_streaks_for_habits', params: {'p_habit_ids': habitIds});
    final streakByHabit = <String, int>{
      for (final row in (streakRows as List))
        row['habit_id'] as String: row['streak'] as int? ?? 0,
    };

    return linkRows.map((row) {
      final userHabit = habitsById[row['user_habit_id']]!;
      final friendHabit = habitsById[row['friend_habit_id']]!;
      final userStreak = streakByHabit[userHabit['id']] ?? 0;
      final friendStreak = streakByHabit[friendHabit['id']] ?? 0;
      return HabitLink(
        id: row['id'] as String,
        userHabitId: userHabit['id'] as String,
        userHabitName: userHabit['name'] as String,
        userHabitIcon: userHabit['icon_key'] as String,
        friendHabitId: friendHabit['id'] as String,
        friendHabitName: friendHabit['name'] as String,
        friendHabitIcon: friendHabit['icon_key'] as String,
        friendshipId: row['friendship_id'] as String,
        friendId: friendHabit['user_id'] as String,
        isActive: row['is_active'] as bool,
        coStreak: userStreak < friendStreak ? userStreak : friendStreak,
      );
    }).toList();
  }

  Future<void> createLink({
    required String userHabitId,
    required String friendHabitId,
    required String friendshipId,
  }) async {
    await supabase.from('habit_links').insert({
      'user_habit_id': userHabitId,
      'friend_habit_id': friendHabitId,
      'friendship_id': friendshipId,
    });
    ref.invalidateSelf();
  }

  Future<void> toggleActive(String linkId, bool value) async {
    await supabase.from('habit_links').update({'is_active': value}).eq('id', linkId);
    ref.invalidateSelf();
  }
}
