import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cadence/theme/app_theme.dart';
import 'package:cadence/widgets/async_value_view.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: child),
      );

  group('AsyncValueView', () {
    testWidgets('renders data via builder', (tester) async {
      await tester.pumpWidget(wrap(
        AsyncValueView<String>(
          value: const AsyncData('hello'),
          onRetry: () {},
          builder: (data) => Text(data),
        ),
      ));
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('renders spinner while loading', (tester) async {
      await tester.pumpWidget(wrap(
        AsyncValueView<String>(
          value: const AsyncLoading(),
          onRetry: () {},
          builder: (data) => Text(data),
        ),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders error card with working retry', (tester) async {
      var retried = false;
      await tester.pumpWidget(wrap(
        AsyncValueView<String>(
          value: AsyncError(Exception('boom'), StackTrace.current),
          onRetry: () => retried = true,
          builder: (data) => Text(data),
        ),
      ));
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining("Couldn't load"), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });
  });
}
