import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/habit.dart';

/// Exports habit history as CSV and hands it to the OS share sheet.
///
/// One row per completed day per habit — the long format spreadsheets and
/// pandas both expect, so it pivots without any cleanup.
class ExportService {
  ExportService._();

  static const _headers = [
    'habit',
    'category',
    'type',
    'frequency',
    'goal_value',
    'goal_unit',
    'completed_on',
    'quantity',
    'note',
  ];

  /// Escapes one CSV field per RFC 4180: wrap in quotes when the value
  /// contains a comma, quote or newline, and double any embedded quotes.
  /// Habit names are free text, so this is not optional.
  static String escapeField(String value) {
    final needsQuotes = value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuotes) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  static String _row(List<String> fields) => fields.map(escapeField).join(',');

  /// Builds the full CSV document for [habits]. Rows are sorted by habit name
  /// then date so the output is stable between exports.
  static String buildCsv(List<Habit> habits) {
    final rows = <List<String>>[];
    for (final habit in habits) {
      final dates = habit.completionHistory.toList()..sort();
      for (final date in dates) {
        final detail = habit.completionDetails[date];
        rows.add([
          habit.name,
          habit.category,
          _typeLabel(habit),
          _frequencyLabel(habit),
          habit.durationValue > 0 ? '${habit.durationValue}' : '',
          habit.durationValue > 0 ? habit.durationUnit : '',
          date,
          detail?.quantity != null ? '${detail!.quantity}' : '',
          detail?.note ?? '',
        ]);
      }
    }
    rows.sort((a, b) {
      final byName = a[0].compareTo(b[0]);
      return byName != 0 ? byName : a[6].compareTo(b[6]);
    });

    final buffer = StringBuffer()..writeln(_row(_headers));
    for (final row in rows) {
      buffer.writeln(_row(row));
    }
    return buffer.toString();
  }

  static String _typeLabel(Habit h) {
    switch (h.habitType) {
      case HabitType.build:
        return 'build';
      case HabitType.breakHabit:
        return 'break';
      case HabitType.custom:
        return h.customTypeLabel ?? 'custom';
    }
  }

  static String _frequencyLabel(Habit h) {
    switch (h.frequency) {
      case FrequencyType.daily:
        return 'daily';
      case FrequencyType.timesPerWeek:
        return '${h.timesPerWeek}x per week';
      case FrequencyType.specificDays:
        const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return h.specificDays
            .where((i) => i >= 0 && i < 7)
            .map((i) => labels[i])
            .join(' ');
    }
  }

  /// Writes the CSV to a temp file and opens the share sheet.
  /// Returns false when there's nothing to export.
  static Future<bool> share(List<Habit> habits) async {
    final hasHistory = habits.any((h) => h.completionHistory.isNotEmpty);
    if (!hasHistory) return false;

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().split('T').first;
    final file = File('${dir.path}/cadence-export-$stamp.csv');
    await file.writeAsString(buildCsv(habits));

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Cadence habit history',
      ),
    );
    return true;
  }
}
