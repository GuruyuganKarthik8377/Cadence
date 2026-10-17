import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/achievement_service.dart';
import 'auth_provider.dart';
import 'friend_provider.dart';
import 'habit_provider.dart';

/// The signed-in user's badges, unlocked ones first.
///
/// Rebuilds when habits or friends change, and inserts anything newly
/// qualified on the way through — so opening the profile is what awards a
/// badge. No trigger, no cron: the rules need the app's own streak logic.
final achievementsProvider =
    AsyncNotifierProvider<AchievementNotifier, List<EarnedAchievement>>(
  AchievementNotifier.new,
);

class AchievementNotifier extends AsyncNotifier<List<EarnedAchievement>> {
  @override
  Future<List<EarnedAchievement>> build() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return const [];

    final habits = ref.watch(habitsProvider).valueOrNull ?? const [];
    final friendCount =
        ref.watch(friendsProvider).valueOrNull?.friends.length ?? 0;

    var unlocked = await _fetch(userId);

    // Award anything newly earned. Failures are swallowed: a badge is a
    // flourish, and it must never be what stops the profile rendering.
    final qualifying = qualifyingAchievements(
      habits: habits,
      friendCount: friendCount,
    );
    final missing = qualifying.difference(unlocked.keys.toSet());
    if (missing.isNotEmpty) {
      try {
        await supabase.from('achievements').insert([
          for (final key in missing) {'user_id': userId, 'key': key},
        ]);
        unlocked = await _fetch(userId);
      } catch (_) {
        // Already-unlocked rows collide on the unique index; nothing to do.
      }
    }

    return [
      for (final a in achievementCatalogue)
        EarnedAchievement(achievement: a, unlockedOn: unlocked[a.key]),
    ]..sort((a, b) {
        if (a.isUnlocked != b.isUnlocked) return a.isUnlocked ? -1 : 1;
        return 0;
      });
  }

  Future<Map<String, DateTime>> _fetch(String userId) async {
    final rows = await supabase
        .from('achievements')
        .select('key, unlocked_on')
        .eq('user_id', userId);
    return {
      for (final row in rows)
        row['key'] as String:
            DateTime.parse(row['unlocked_on'] as String),
    };
  }
}

/// A friend's unlocked badges, for their detail page. Only the ones they
/// actually have — an empty list is a friend with none, not an error.
final friendAchievementsProvider =
    FutureProvider.family<List<Achievement>, String>((ref, friendId) async {
  final rows = await supabase
      .from('achievements')
      .select('key')
      .eq('user_id', friendId);
  final keys = {for (final row in rows) row['key'] as String};
  return [
    for (final a in achievementCatalogue)
      if (keys.contains(a.key)) a,
  ];
});
