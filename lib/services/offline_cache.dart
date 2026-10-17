import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/habit.dart';

/// A completion toggle made while offline, waiting to be replayed.
class PendingToggle {
  final String habitId;
  /// yyyy-MM-dd.
  final String date;
  /// True when the user marked it done, false when they un-did it.
  final bool completed;

  const PendingToggle({
    required this.habitId,
    required this.date,
    required this.completed,
  });

  Map<String, dynamic> toJson() =>
      {'habit_id': habitId, 'date': date, 'completed': completed};

  factory PendingToggle.fromJson(Map<String, dynamic> json) => PendingToggle(
        habitId: json['habit_id'] as String,
        date: json['date'] as String,
        completed: json['completed'] as bool,
      );
}

/// Local cache of the habit list plus a queue of writes made while offline.
///
/// Backed by shared_preferences rather than a database: the payload is one
/// user's habits, read and written whole, so there is nothing to query.
class OfflineCache {
  OfflineCache._();

  static const _habitsKey = 'cache.habits.v1';
  static const _queueKey = 'cache.pending_toggles.v1';

  /// Whether [error] means "the network is unavailable" rather than "the
  /// server rejected this". Only the former is worth queueing — replaying a
  /// rejected write (the run/walk completion gate, an RLS denial) would just
  /// fail again forever.
  static bool isOffline(Object error) {
    if (error is SocketException || error is HttpException) return true;
    if (error is TimeoutException) return true;
    final text = error.toString().toLowerCase();
    return text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection closed') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('software caused connection abort');
  }

  static Future<void> saveHabits(List<Habit> habits) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _habitsKey,
        jsonEncode([for (final h in habits) h.toCacheJson()]),
      );
    } catch (e) {
      debugPrint('habit cache write skipped: $e');
    }
  }

  /// The last successfully fetched habit list, or null when there is none.
  static Future<List<Habit>?> loadHabits() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_habitsKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw) as List;
      return [
        for (final entry in decoded)
          Habit.fromCacheJson(entry as Map<String, dynamic>),
      ];
    } catch (e) {
      // A cache written by an older build can fail to parse — treat it as
      // absent rather than blocking the app.
      debugPrint('habit cache read skipped: $e');
      return null;
    }
  }

  static Future<void> clearHabits() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_habitsKey);
      await prefs.remove(_queueKey);
    } catch (_) {}
  }

  static Future<List<PendingToggle>> pendingToggles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_queueKey);
      if (raw == null) return [];
      return [
        for (final entry in jsonDecode(raw) as List)
          PendingToggle.fromJson(entry as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  /// Queues a toggle, collapsing any earlier entry for the same habit+day so
  /// tapping twice offline settles on the final state instead of replaying
  /// both taps.
  static Future<void> queueToggle(PendingToggle toggle) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queue = await pendingToggles()
        ..removeWhere(
            (t) => t.habitId == toggle.habitId && t.date == toggle.date);
      queue.add(toggle);
      await prefs.setString(
        _queueKey,
        jsonEncode([for (final t in queue) t.toJson()]),
      );
    } catch (e) {
      debugPrint('toggle queue write skipped: $e');
    }
  }

  static Future<void> clearQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_queueKey);
    } catch (_) {}
  }
}
