/// A completed accelerometer-tracked run, logged against a habit.
class RunSession {
  final String id;
  final String habitId;
  final DateTime startedAt;
  final int durationSeconds;
  final int steps;
  final double distanceMeters;

  const RunSession({
    required this.id,
    required this.habitId,
    required this.startedAt,
    required this.durationSeconds,
    required this.steps,
    required this.distanceMeters,
  });

  /// Average pace, minutes per kilometre. Null if no distance was covered.
  double? get paceMinPerKm {
    if (distanceMeters <= 0) return null;
    final km = distanceMeters / 1000;
    final minutes = durationSeconds / 60;
    return minutes / km;
  }

  factory RunSession.fromJson(Map<String, dynamic> json) => RunSession(
        id: json['id'] as String,
        habitId: json['habit_id'] as String,
        startedAt: DateTime.parse(json['started_at'] as String),
        durationSeconds: json['duration_seconds'] as int,
        steps: json['steps'] as int,
        distanceMeters: (json['distance_meters'] as num).toDouble(),
      );

  Map<String, dynamic> toInsertJson(String userId) => {
        'habit_id': habitId,
        'user_id': userId,
        'started_at': startedAt.toIso8601String(),
        'duration_seconds': durationSeconds,
        'steps': steps,
        'distance_meters': distanceMeters,
      };
}
