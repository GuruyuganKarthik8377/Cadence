import 'package:flutter_test/flutter_test.dart';
import 'package:cadence/models/habit.dart';
import 'package:cadence/providers/habit_provider.dart';

List<Habit> _list(List<String> names) => [
      for (var i = 0; i < names.length; i++)
        Habit(
          id: names[i],
          name: names[i],
          iconOrEmoji: 'star',
          category: 'Fitness',
          habitType: HabitType.build,
          frequency: FrequencyType.daily,
          sortOrder: i,
        ),
    ];

List<String> _ids(List<Habit> habits) => habits.map((h) => h.id).toList();

void main() {
  group('reorderedHabits', () {
    test('moves an item down', () {
      final result = reorderedHabits(_list(['a', 'b', 'c', 'd']), 0, 2);
      expect(_ids(result), ['b', 'c', 'a', 'd']);
    });

    test('moves an item up', () {
      final result = reorderedHabits(_list(['a', 'b', 'c', 'd']), 3, 1);
      expect(_ids(result), ['a', 'd', 'b', 'c']);
    });

    test('moves the first item to the end', () {
      final result = reorderedHabits(_list(['a', 'b', 'c']), 0, 2);
      expect(_ids(result), ['b', 'c', 'a']);
    });

    test('moves the last item to the front', () {
      final result = reorderedHabits(_list(['a', 'b', 'c']), 2, 0);
      expect(_ids(result), ['c', 'a', 'b']);
    });

    test('renumbers sortOrder to match the new positions', () {
      final result = reorderedHabits(_list(['a', 'b', 'c']), 2, 0);
      expect(result.map((h) => h.sortOrder).toList(), [0, 1, 2]);
      expect(result[0].id, 'c');
      expect(result[0].sortOrder, 0);
    });

    test('never drops or duplicates an item', () {
      final source = _list(['a', 'b', 'c', 'd', 'e']);
      for (var from = 0; from < 5; from++) {
        for (var to = 0; to < 5; to++) {
          final result = reorderedHabits(source, from, to);
          expect(result.length, 5, reason: 'move $from -> $to changed length');
          expect(_ids(result).toSet(), {'a', 'b', 'c', 'd', 'e'},
              reason: 'move $from -> $to lost or duplicated an item');
        }
      }
    });

    test('a no-op move returns the original list untouched', () {
      final source = _list(['a', 'b', 'c']);
      expect(identical(reorderedHabits(source, 1, 1), source), isTrue);
    });

    test('out-of-range indices are ignored rather than throwing', () {
      final source = _list(['a', 'b', 'c']);
      expect(identical(reorderedHabits(source, -1, 1), source), isTrue);
      expect(identical(reorderedHabits(source, 1, 9), source), isTrue);
      expect(identical(reorderedHabits(source, 9, 1), source), isTrue);
    });

    test('an empty list is safe', () {
      expect(reorderedHabits(const <Habit>[], 0, 0), isEmpty);
    });
  });
}
