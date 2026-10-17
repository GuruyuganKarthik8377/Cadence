import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'activity_feed_provider.dart';
import 'auth_provider.dart';

/// The reaction palette. Small and fixed — a full emoji picker turns a
/// one-tap gesture into a decision.
const reactionEmojis = ['🔥', '💪', '👏', '🎉'];

/// Reactions on one completion: how many of each emoji, and which ones the
/// signed-in user has already left.
class ReactionSummary {
  final Map<String, int> counts;
  final Set<String> mine;

  const ReactionSummary({this.counts = const {}, this.mine = const {}});

  int countOf(String emoji) => counts[emoji] ?? 0;
  bool didReact(String emoji) => mine.contains(emoji);
  bool get isEmpty => counts.isEmpty;
}

/// Reactions for every completion currently in the activity feed, keyed by
/// completion id. Rebuilds with the feed.
final reactionsProvider =
    AsyncNotifierProvider<ReactionNotifier, Map<String, ReactionSummary>>(
  ReactionNotifier.new,
);

class ReactionNotifier extends AsyncNotifier<Map<String, ReactionSummary>> {
  @override
  Future<Map<String, ReactionSummary>> build() async {
    final feed = await ref.watch(activityFeedProvider.future);
    final ids = feed.map((e) => e.completionId).toList();
    if (ids.isEmpty) return {};

    final userId = supabase.auth.currentUser?.id;
    final rows = await supabase
        .from('habit_reactions')
        .select('completion_id, actor_id, emoji')
        .inFilter('completion_id', ids);

    final counts = <String, Map<String, int>>{};
    final mine = <String, Set<String>>{};
    for (final row in rows) {
      final completionId = row['completion_id'] as String;
      final emoji = row['emoji'] as String;
      counts.putIfAbsent(completionId, () => {});
      counts[completionId]![emoji] = (counts[completionId]![emoji] ?? 0) + 1;
      if (row['actor_id'] == userId) {
        mine.putIfAbsent(completionId, () => {}).add(emoji);
      }
    }

    return {
      for (final id in counts.keys)
        id: ReactionSummary(
          counts: counts[id]!,
          mine: mine[id] ?? const {},
        ),
    };
  }

  /// Adds or removes the signed-in user's [emoji] on [completionId].
  /// Applied locally first — a reaction should feel instant.
  Future<void> toggle(String completionId, String emoji) async {
    final userId = supabase.auth.currentUser!.id;
    final current = state.valueOrNull ?? const {};
    final summary = current[completionId] ?? const ReactionSummary();
    final had = summary.didReact(emoji);

    state = AsyncData({
      ...current,
      completionId: ReactionSummary(
        counts: {
          ...summary.counts,
          emoji: (summary.countOf(emoji) + (had ? -1 : 1)).clamp(0, 1 << 30),
        }..removeWhere((_, count) => count <= 0),
        mine: had
            ? (summary.mine.toSet()..remove(emoji))
            : (summary.mine.toSet()..add(emoji)),
      ),
    });

    try {
      if (had) {
        await supabase
            .from('habit_reactions')
            .delete()
            .eq('completion_id', completionId)
            .eq('actor_id', userId)
            .eq('emoji', emoji);
      } else {
        await supabase.from('habit_reactions').insert({
          'completion_id': completionId,
          'actor_id': userId,
          'emoji': emoji,
        });
      }
    } catch (_) {
      ref.invalidateSelf();
      rethrow;
    }
  }
}
