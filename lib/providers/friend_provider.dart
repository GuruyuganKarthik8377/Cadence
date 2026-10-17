import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/friend.dart';
import '../models/profile.dart';
import 'auth_provider.dart';

final friendsProvider = AsyncNotifierProvider<FriendNotifier, FriendsState>(
  FriendNotifier.new,
);

class FriendsState {
  final List<Friend> friends;
  final List<Friend> pendingRequests;

  const FriendsState({this.friends = const [], this.pendingRequests = const []});
}

class FriendNotifier extends AsyncNotifier<FriendsState> {
  RealtimeChannel? _channel;

  @override
  Future<FriendsState> build() async {
    ref.onDispose(() {
      if (_channel != null) supabase.removeChannel(_channel!);
    });
    _subscribeToFriendshipChanges();
    return _fetch();
  }

  /// Refresh when a friendship row involving this user changes. Uses the
  /// realtime channel API (fires only on INSERT/UPDATE/DELETE) rather than
  /// .stream() — a stream emits its initial snapshot on subscribe, which
  /// would invalidate → rebuild → resubscribe in an endless loop.
  void _subscribeToFriendshipChanges() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    _channel = supabase
        .channel('public:friendships:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'friendships',
          callback: (_) => ref.invalidateSelf(),
        )
        .subscribe();
  }

  Future<FriendsState> _fetch() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return const FriendsState();

    final rows = await supabase
        .from('friendships')
        .select()
        .or('requester_id.eq.$userId,addressee_id.eq.$userId');

    final accepted = rows.where((r) => r['status'] == 'accepted').toList();
    final pending = rows
        .where((r) => r['status'] == 'pending' && r['addressee_id'] == userId)
        .toList();

    final otherIds = {
      ...accepted.map((r) => r['requester_id'] == userId ? r['addressee_id'] as String : r['requester_id'] as String),
      ...pending.map((r) => r['requester_id'] as String),
    }.toList();

    if (otherIds.isEmpty) return const FriendsState();

    final profileRows = await supabase.from('profiles').select().inFilter('id', otherIds);
    final profilesById = {for (final p in profileRows) p['id'] as String: Profile.fromJson(p)};

    final acceptedFriendshipIds = accepted.map((r) => r['id'] as String).toList();
    final linkCounts = <String, int>{};
    var linksByFriendship = <String, List<Map<String, dynamic>>>{};
    if (acceptedFriendshipIds.isNotEmpty) {
      final linkRows = await supabase
          .from('habit_links')
          .select('friendship_id, friend_habit_id, is_active')
          .inFilter('friendship_id', acceptedFriendshipIds)
          .eq('is_active', true);
      for (final row in linkRows) {
        final fid = row['friendship_id'] as String;
        linkCounts[fid] = (linkCounts[fid] ?? 0) + 1;
        linksByFriendship.putIfAbsent(fid, () => []).add(row);
      }
    }

    // Streaks for every linked friend habit in ONE round trip. Calling
    // get_current_streak() per link was an N+1 that made the friends list
    // slower with every friend and every linked habit.
    final streakByHabit = <String, int>{};
    final linkedHabitIds = linksByFriendship.values
        .expand((links) => links.map((l) => l['friend_habit_id'] as String))
        .toSet()
        .toList();
    if (linkedHabitIds.isNotEmpty) {
      final streakRows = await supabase
          .rpc('get_streaks_for_habits', params: {'p_habit_ids': linkedHabitIds});
      for (final row in (streakRows as List)) {
        streakByHabit[row['habit_id'] as String] = row['streak'] as int? ?? 0;
      }
    }

    final friends = <Friend>[];
    for (final row in accepted) {
      final otherId = row['requester_id'] == userId ? row['addressee_id'] as String : row['requester_id'] as String;
      final profile = profilesById[otherId];
      if (profile == null) continue;

      final friendshipId = row['id'] as String;
      final links = linksByFriendship[friendshipId] ?? const [];
      int bestStreak = 0;
      for (final link in links) {
        final streak = streakByHabit[link['friend_habit_id'] as String] ?? 0;
        if (streak > bestStreak) bestStreak = streak;
      }

      final daysConnected = DateTime.now().difference(DateTime.parse(row['updated_at'] as String)).inDays;

      friends.add(Friend(
        id: otherId,
        friendshipId: friendshipId,
        name: profile.displayName,
        username: '@${profile.username}',
        avatarUrl: profile.avatarUrl ?? '',
        status: FriendStatus.connected,
        habitsLinked: linkCounts[friendshipId] ?? 0,
        currentStreak: bestStreak,
        daysConnected: daysConnected,
      ));
    }

    final pendingRequests = pending.map((row) {
      final otherId = row['requester_id'] as String;
      final profile = profilesById[otherId];
      return Friend(
        id: otherId,
        friendshipId: row['id'] as String,
        name: profile?.displayName ?? '',
        username: profile != null ? '@${profile.username}' : '',
        avatarUrl: profile?.avatarUrl ?? '',
        status: FriendStatus.pendingIncoming,
      );
    }).where((f) => f.name.isNotEmpty).toList();

    return FriendsState(friends: friends, pendingRequests: pendingRequests);
  }

  Future<List<Profile>> searchUsers(String query) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null || query.trim().isEmpty) return [];

    final rows = await supabase
        .from('profiles')
        .select()
        .or('username.ilike.*$query*,display_name.ilike.*$query*')
        .neq('id', userId)
        .limit(20);

    final results = rows.map((r) => Profile.fromJson(r)).toList();

    // Exclude users who are already friends or have a pending request either way.
    final existing = await supabase
        .from('friendships')
        .select('requester_id, addressee_id')
        .or('requester_id.eq.$userId,addressee_id.eq.$userId');
    final excludedIds = <String>{
      for (final row in existing) ...[row['requester_id'] as String, row['addressee_id'] as String],
    }..remove(userId);

    return results.where((p) => !excludedIds.contains(p.id)).toList();
  }

  Future<void> sendRequest(String profileId) async {
    final userId = supabase.auth.currentUser!.id;
    await supabase.from('friendships').insert({
      'requester_id': userId,
      'addressee_id': profileId,
      'status': 'pending',
    });
  }

  Future<void> acceptRequest(String friendshipId) async {
    await supabase.from('friendships').update({'status': 'accepted'}).eq('id', friendshipId);
    ref.invalidateSelf();
  }

  Future<void> declineRequest(String friendshipId) async {
    await supabase.from('friendships').update({'status': 'declined'}).eq('id', friendshipId);
    ref.invalidateSelf();
  }

  Future<void> removeFriend(String friendshipId) async {
    await supabase.from('friendships').delete().eq('id', friendshipId);
    ref.invalidateSelf();
  }

  /// Blocks [profileId]. Uses the security-definer RPC so it can atomically
  /// set blocker_id without client code touching that column directly.
  Future<void> blockUser(String profileId) async {
    await supabase.rpc('block_user', params: {'p_target_id': profileId});
    // Blocked row is now status='blocked', so _fetch skips it — invalidate
    // to clear them from the list and search exclusion stays correct.
    ref.invalidateSelf();
  }

  /// Submits a report. Inserts into user_reports; the server team reviews via
  /// service role. Optional [reason] is capped at 500 chars server-side.
  Future<void> reportUser(String profileId, {String? reason}) async {
    await supabase.from('user_reports').insert({
      'reported_id': profileId,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }
}
