enum FriendStatus { connected, pendingIncoming, pendingSent }

class Friend {
  final String id; // the other party's profile id
  final String friendshipId; // the friendships row id — needed to accept/decline/remove
  final String name;
  final String username;
  final String avatarUrl;
  final FriendStatus status;
  final int habitsLinked;
  final int currentStreak;
  final int daysConnected;

  const Friend({
    required this.id,
    required this.friendshipId,
    required this.name,
    required this.username,
    required this.avatarUrl,
    required this.status,
    this.habitsLinked = 0,
    this.currentStreak = 0,
    this.daysConnected = 0,
  });
}
