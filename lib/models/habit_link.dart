class HabitLink {
  final String id;
  final String userHabitId;
  final String userHabitName;
  final String userHabitIcon; // icon_key, rendered via habitIconData()
  final String friendHabitId;
  final String friendHabitName;
  final String friendHabitIcon; // icon_key
  final String friendshipId;
  final String friendId; // the friend's profile id
  final bool isActive;
  /// Days both sides of this pair have kept their streak alive —
  /// min(userHabit streak, friendHabit streak). Not a separate counter: a
  /// shared streak breaks the moment either side misses, so the lower of the
  /// two streaks already *is* the co-streak.
  final int coStreak;

  const HabitLink({
    required this.id,
    required this.userHabitId,
    required this.userHabitName,
    required this.userHabitIcon,
    required this.friendHabitId,
    required this.friendHabitName,
    required this.friendHabitIcon,
    required this.friendshipId,
    required this.friendId,
    this.isActive = true,
    this.coStreak = 0,
  });
}
