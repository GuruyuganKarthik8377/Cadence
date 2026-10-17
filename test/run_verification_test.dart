import 'package:flutter_test/flutter_test.dart';
import 'package:cadence/models/habit.dart';

Habit _habit({required String name, required String category}) => Habit(
      id: 'h1',
      name: name,
      iconOrEmoji: 'footprints',
      category: category,
      habitType: HabitType.build,
      frequency: FrequencyType.daily,
    );

void main() {
  group('isRunOrWalkHabit', () {
    test('matches habits named after running', () {
      expect(isRunOrWalkHabit(_habit(name: 'Morning Run', category: 'Fitness')),
          isTrue);
      expect(isRunOrWalkHabit(_habit(name: 'Running', category: 'Health')),
          isTrue);
      expect(isRunOrWalkHabit(_habit(name: '5k Runner Training', category: 'Fitness')),
          isTrue);
    });

    test('matches habits named after walking', () {
      expect(isRunOrWalkHabit(_habit(name: 'Evening Walk', category: 'Health')),
          isTrue);
      expect(isRunOrWalkHabit(_habit(name: 'Walking the dog', category: 'Health')),
          isTrue);
    });

    test('matches via category even if the name does not mention it', () {
      expect(
          isRunOrWalkHabit(_habit(name: 'Morning Session', category: 'Running')),
          isTrue);
    });

    test('does not match unrelated habits', () {
      expect(
          isRunOrWalkHabit(_habit(name: 'Grocery Shopping', category: 'Errands')),
          isFalse);
      expect(isRunOrWalkHabit(_habit(name: 'Sunbathe', category: 'Wellness')),
          isFalse);
      expect(isRunOrWalkHabit(_habit(name: 'Deep Work', category: 'Productivity')),
          isFalse);
      // Substrings of unrelated words shouldn't false-positive: "walk" isn't
      // a substring of these, but this guards the boundary behavior.
      expect(isRunOrWalkHabit(_habit(name: 'Read a Book', category: 'Learning')),
          isFalse);
    });

    test('matching is case-insensitive', () {
      expect(isRunOrWalkHabit(_habit(name: 'MORNING RUN', category: 'fitness')),
          isTrue);
    });
  });
}
