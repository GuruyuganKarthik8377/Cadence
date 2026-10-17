import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/habit.dart';

/// Pushes today's habits to the Android home screen widget.
///
/// The widget is a renderer only — it reads what we write here and never
/// touches the network, so there is no auth or Supabase code on the Android
/// side. Everything is best-effort: a device with no widget placed, or a
/// platform that has none, must not affect the app.
class WidgetService {
  WidgetService._();

  static const _appGroupId = 'com.harishram.cadence.widget';
  static const _androidName = 'CadenceWidgetProvider';

  /// How many rows the widget layout actually has.
  static const _visibleRows = 3;

  static Future<void> init() async {
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
    } catch (e) {
      debugPrint('widget init skipped: $e');
    }
  }

  /// Rewrites the widget from [habits]. Only habits scheduled today are shown,
  /// incomplete first, so the widget surfaces what's left rather than what's
  /// already done.
  static Future<void> update(List<Habit> habits) async {
    try {
      final today = DateTime.now();
      final due = habits.where((h) => h.isScheduledOn(today)).toList()
        ..sort((a, b) {
          final aDone = a.isCompletedOn(today) ? 1 : 0;
          final bDone = b.isCompletedOn(today) ? 1 : 0;
          if (aDone != bDone) return aDone - bDone;
          return a.sortOrder.compareTo(b.sortOrder);
        });

      final doneCount = due.where((h) => h.isCompletedOn(today)).length;

      await HomeWidget.saveWidgetData<String>(
        'habits',
        jsonEncode([
          for (final habit in due.take(_visibleRows))
            {
              'id': habit.id,
              'name': habit.name,
              'done': habit.isCompletedOn(today),
            },
        ]),
      );
      await HomeWidget.saveWidgetData<int>('done_count', doneCount);
      await HomeWidget.saveWidgetData<int>('total_count', due.length);
      await HomeWidget.updateWidget(androidName: _androidName);
    } catch (e) {
      debugPrint('widget update skipped: $e');
    }
  }

  /// The habit id from a `cadence://toggle?habitId=…` launch, or null when the
  /// uri is anything else (the Supabase auth callback also arrives here).
  static String? habitIdFromUri(Uri? uri) {
    if (uri == null) return null;
    if (uri.scheme != 'cadence' || uri.host != 'toggle') return null;
    final id = uri.queryParameters['habitId'];
    return (id == null || id.isEmpty) ? null : id;
  }
}
