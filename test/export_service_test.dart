import 'package:flutter_test/flutter_test.dart';
import 'package:cadence/models/habit.dart';
import 'package:cadence/services/export_service.dart';

Habit _habit({
  required String name,
  String category = 'Fitness',
  FrequencyType frequency = FrequencyType.daily,
  List<int> specificDays = const [],
  int timesPerWeek = 1,
  int durationValue = 0,
  String durationUnit = 'minutes',
  List<String> history = const [],
  Map<String, CompletionDetail> details = const {},
}) =>
    Habit(
      id: 'h-$name',
      name: name,
      iconOrEmoji: 'star',
      category: category,
      habitType: HabitType.build,
      frequency: frequency,
      specificDays: specificDays,
      timesPerWeek: timesPerWeek,
      durationValue: durationValue,
      durationUnit: durationUnit,
      completionHistory: history,
      completionDetails: details,
    );

void main() {
  group('escapeField', () {
    test('leaves plain values alone', () {
      expect(ExportService.escapeField('Morning Run'), 'Morning Run');
    });

    test('quotes a value containing a comma', () {
      expect(ExportService.escapeField('Run, then stretch'),
          '"Run, then stretch"');
    });

    test('doubles embedded quotes and wraps', () {
      expect(ExportService.escapeField('Read "Dune"'), '"Read ""Dune"""');
    });

    test('quotes a value containing a newline', () {
      expect(ExportService.escapeField('Gym\nsession'), '"Gym\nsession"');
    });

    test('quotes a value containing a carriage return', () {
      expect(ExportService.escapeField('Gym\rsession'), '"Gym\rsession"');
    });
  });

  group('buildCsv', () {
    test('emits a header even with no history', () {
      final csv = ExportService.buildCsv([_habit(name: 'Run')]);
      expect(csv.trim(),
          'habit,category,type,frequency,goal_value,goal_unit,completed_on,quantity,note');
    });

    test('emits one row per completed day', () {
      final csv = ExportService.buildCsv([
        _habit(name: 'Run', history: ['2026-01-02', '2026-01-01']),
      ]);
      final lines = csv.trim().split('\n');
      expect(lines.length, 3); // header + 2
      // Dates sort ascending within a habit.
      expect(lines[1], contains('2026-01-01'));
      expect(lines[2], contains('2026-01-02'));
    });

    test('a comma in the habit name cannot shift the column count', () {
      final csv = ExportService.buildCsv([
        _habit(name: 'Run, walk, repeat', history: ['2026-01-01']),
      ]);
      final row = csv.trim().split('\n')[1];
      expect(row, startsWith('"Run, walk, repeat",'));
      // Nine fields means the commas stayed inside the quoted name.
      expect(_countFields(row), 9);
    });

    test('a quote in the habit name round-trips', () {
      final csv = ExportService.buildCsv([
        _habit(name: 'Read "Dune"', history: ['2026-01-01']),
      ]);
      final row = csv.trim().split('\n')[1];
      expect(row, startsWith('"Read ""Dune""",'));
      expect(_countFields(row), 9);
    });

    test('goal columns stay empty when no goal is set', () {
      final csv = ExportService.buildCsv([
        _habit(name: 'Run', history: ['2026-01-01']),
      ]);
      expect(csv.trim().split('\n')[1], 'Run,Fitness,build,daily,,,2026-01-01,,');
    });

    test('goal columns carry through when set', () {
      final csv = ExportService.buildCsv([
        _habit(
            name: 'Read',
            durationValue: 30,
            durationUnit: 'pages',
            history: ['2026-01-01']),
      ]);
      expect(csv.trim().split('\n')[1],
          'Read,Fitness,build,daily,30,pages,2026-01-01,,');
    });

    test('specificDays renders the selected weekdays', () {
      final csv = ExportService.buildCsv([
        _habit(
          name: 'Gym',
          frequency: FrequencyType.specificDays,
          specificDays: const [0, 2, 4],
          history: ['2026-01-01'],
        ),
      ]);
      expect(csv, contains('Mon Wed Fri'));
    });

    test('carries quantity and note when a day has them', () {
      final csv = ExportService.buildCsv([
        _habit(
          name: 'Read',
          durationValue: 30,
          durationUnit: 'pages',
          history: ['2026-01-01'],
          details: {
            '2026-01-01':
                const CompletionDetail(quantity: 12, note: 'slow start'),
          },
        ),
      ]);
      expect(csv.trim().split('\n')[1],
          'Read,Fitness,build,daily,30,pages,2026-01-01,12,slow start');
    });

    test('a comma in a note stays inside its own field', () {
      final csv = ExportService.buildCsv([
        _habit(
          name: 'Read',
          history: ['2026-01-01'],
          details: {
            '2026-01-01': const CompletionDetail(note: 'tired, but done'),
          },
        ),
      ]);
      final row = csv.trim().split('\n')[1];
      expect(row, endsWith('"tired, but done"'));
      expect(_countFields(row), 9);
    });

    test('rows are grouped and sorted by habit name', () {
      final csv = ExportService.buildCsv([
        _habit(name: 'Zebra', history: ['2026-01-01']),
        _habit(name: 'Apple', history: ['2026-01-01']),
      ]);
      final lines = csv.trim().split('\n');
      expect(lines[1], startsWith('Apple'));
      expect(lines[2], startsWith('Zebra'));
    });
  });
}

/// Counts top-level CSV fields, ignoring commas inside quoted sections.
int _countFields(String row) {
  var fields = 1;
  var inQuotes = false;
  for (var i = 0; i < row.length; i++) {
    final ch = row[i];
    if (ch == '"') {
      inQuotes = !inQuotes;
    } else if (ch == ',' && !inQuotes) {
      fields++;
    }
  }
  return fields;
}
