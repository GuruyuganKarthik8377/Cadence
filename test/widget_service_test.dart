import 'package:flutter_test/flutter_test.dart';
import 'package:cadence/services/widget_service.dart';

void main() {
  group('habitIdFromUri', () {
    test('extracts the habit id from a widget tap', () {
      final uri = Uri.parse('cadence://toggle?habitId=abc-123');
      expect(WidgetService.habitIdFromUri(uri), 'abc-123');
    });

    test('ignores the Supabase auth callback', () {
      // Both deep links share the cadence:// scheme, so the host has to be
      // what distinguishes them — otherwise signing in would toggle a habit.
      final uri = Uri.parse('cadence://auth-callback?code=xyz');
      expect(WidgetService.habitIdFromUri(uri), isNull);
    });

    test('ignores a foreign scheme', () {
      expect(
        WidgetService.habitIdFromUri(Uri.parse('https://toggle?habitId=abc')),
        isNull,
      );
    });

    test('returns null when the id is missing or blank', () {
      expect(WidgetService.habitIdFromUri(Uri.parse('cadence://toggle')), isNull);
      expect(
        WidgetService.habitIdFromUri(Uri.parse('cadence://toggle?habitId=')),
        isNull,
      );
    });

    test('returns null for a null uri', () {
      expect(WidgetService.habitIdFromUri(null), isNull);
    });

    test('handles a uuid with hyphens intact', () {
      const id = '3f2b1c9e-1111-4a2b-9c3d-000000000001';
      expect(
        WidgetService.habitIdFromUri(Uri.parse('cadence://toggle?habitId=$id')),
        id,
      );
    });
  });
}
