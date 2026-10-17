import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// A poke from a friend about a habit you haven't done yet.
class Nudge {
  final String id;
  final String fromName;
  final String fromAvatarUrl;
  final String habitName;
  final DateTime createdAt;

  const Nudge({
    required this.id,
    required this.fromName,
    required this.fromAvatarUrl,
    required this.habitName,
    required this.createdAt,
  });
}

/// Unread nudges addressed to the signed-in user, newest first.
final incomingNudgesProvider =
    AsyncNotifierProvider<NudgeNotifier, List<Nudge>>(NudgeNotifier.new);

class NudgeNotifier extends AsyncNotifier<List<Nudge>> {
  RealtimeChannel? _channel;

  @override
  Future<List<Nudge>> build() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    ref.onDispose(() {
      if (_channel != null) supabase.removeChannel(_channel!);
    });
    _subscribeToNudges(userId);

    final rows = await supabase
        .from('nudges')
        .select('id, created_at, habits(name), profiles!nudges_from_user_id_fkey(display_name, avatar_url)')
        .eq('to_user_id', userId)
        .isFilter('read_at', null)
        .order('created_at', ascending: false)
        .limit(20);

    return rows.map((row) {
      final from = row['profiles'] as Map<String, dynamic>?;
      final habit = row['habits'] as Map<String, dynamic>?;
      return Nudge(
        id: row['id'] as String,
        fromName: from?['display_name'] as String? ?? 'A friend',
        fromAvatarUrl: from?['avatar_url'] as String? ?? '',
        habitName: habit?['name'] as String? ?? 'a habit',
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList();
  }

  /// A nudge is only useful if it lands promptly, so refresh on insert rather
  /// than waiting for the next app launch. Filtered to this user server-side,
  /// so a busy instance doesn't wake every device.
  ///
  /// Channel API only — `.stream()` re-emits its snapshot on subscribe, which
  /// would invalidate → rebuild → resubscribe forever.
  void _subscribeToNudges(String userId) {
    _channel = supabase
        .channel('public:nudges:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'nudges',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'to_user_id',
            value: userId,
          ),
          callback: (_) => ref.invalidateSelf(),
        )
        .subscribe();
  }

  /// Sends a nudge. The unique index caps this at one per friend per habit per
  /// day, so a duplicate comes back as a conflict rather than spamming.
  Future<void> send({
    required String toUserId,
    required String habitId,
    String? message,
  }) async {
    final userId = supabase.auth.currentUser!.id;
    try {
      await supabase.from('nudges').insert({
        'from_user_id': userId,
        'to_user_id': toUserId,
        'habit_id': habitId,
        'message': message,
      });
    } on Object catch (e) {
      if (e.toString().contains('nudges_daily_unique') ||
          e.toString().contains('23505')) {
        throw Exception('You already nudged them about this today.');
      }
      rethrow;
    }
  }

  /// Marks one nudge read and drops it from the list.
  Future<void> dismiss(String nudgeId) async {
    final current = state.valueOrNull ?? const <Nudge>[];
    state = AsyncData([
      for (final n in current)
        if (n.id != nudgeId) n,
    ]);
    try {
      await supabase
          .from('nudges')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', nudgeId);
    } catch (_) {
      ref.invalidateSelf();
      rethrow;
    }
  }
}
