import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';

class ActivityFeedEntry {
  final String friendId;
  final String friendName;
  final String friendAvatarUrl;
  final String habitId;
  final String habitName;
  final String habitIconKey;
  /// The completion this entry describes — reactions hang off it.
  final String completionId;
  final DateTime completedAt;

  const ActivityFeedEntry({
    required this.friendId,
    required this.friendName,
    required this.friendAvatarUrl,
    required this.habitId,
    required this.habitName,
    required this.habitIconKey,
    required this.completionId,
    required this.completedAt,
  });
}

final activityFeedProvider = AsyncNotifierProvider<ActivityFeedNotifier, List<ActivityFeedEntry>>(
  ActivityFeedNotifier.new,
);

class ActivityFeedNotifier extends AsyncNotifier<List<ActivityFeedEntry>> {
  RealtimeChannel? _channel;

  @override
  Future<List<ActivityFeedEntry>> build() async {
    ref.onDispose(() {
      if (_channel != null) supabase.removeChannel(_channel!);
    });
    _subscribeToCompletions();
    return _fetch();
  }

  /// Refresh when any completion is inserted. Channel API only — .stream()
  /// emits its initial snapshot on subscribe, which would invalidate →
  /// rebuild → resubscribe forever (the cause of the buffering bug).
  void _subscribeToCompletions() {
    _channel = supabase
        .channel('public:habit_completions')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'habit_completions',
          callback: (_) => ref.invalidateSelf(),
        )
        .subscribe();
  }

  Future<List<ActivityFeedEntry>> _fetch() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    // No viewer argument: the function derives it from auth.uid() itself.
    // Passing it in meant any caller could ask for anyone else's feed.
    final rows = await supabase.rpc('get_friend_activity');

    return (rows as List).map((row) {
      return ActivityFeedEntry(
        friendId: row['friend_id'] as String,
        friendName: row['friend_name'] as String,
        friendAvatarUrl: row['friend_avatar_url'] as String? ?? '',
        habitId: row['habit_id'] as String,
        habitName: row['habit_name'] as String,
        habitIconKey: row['habit_icon_key'] as String,
        completionId: row['completion_id'] as String,
        completedAt: DateTime.parse(row['completed_at'] as String),
      );
    }).toList();
  }
}
