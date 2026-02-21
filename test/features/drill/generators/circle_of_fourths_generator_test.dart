import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/core/music/circle_of_fifths.dart';
import 'package:jazz_piano_tools/core/music/chord_quality.dart';
import 'package:jazz_piano_tools/core/music/note_name.dart';
import 'package:jazz_piano_tools/core/music/pitch_class.dart';
import 'package:jazz_piano_tools/domain/enums/exercise_mode.dart';
import 'package:jazz_piano_tools/domain/enums/input_type.dart';
import 'package:jazz_piano_tools/domain/models/exercise.dart';
import 'package:jazz_piano_tools/features/drill/generators/circle_of_fourths_generator.dart';

void main() {
  final generator = CircleOfFourthsGenerator();

  group('CircleOfFourthsGenerator - nextKey mode', () {
    final exercise = Exercise(
      id: 'test-cof-next',
      title: 'Circle of Fourths',
      mode: ExerciseMode.drill,
      inputType: InputType.multipleChoice,
      generatorId: 'circleOfFourths',
      config: {'subMode': 'nextKey'},
    );

    test('generates the requested number of questions', () {
      final questions5 = generator.generate(exercise, count: 5);
      expect(questions5.length, 5);

      final questions12 = generator.generate(exercise, count: 12);
      expect(questions12.length, 12);

      final questions1 = generator.generate(exercise, count: 1);
      expect(questions1.length, 1);
    });

    test('expected answers are musically correct fourths', () {
      final fourths = CircleOfFifths.fourthsOrder;
      final questions = generator.generate(exercise, count: 50);

      for (final q in questions) {
        final currentKeyValue = q.metadata['currentKey'] as int;
        final nextKeyValue = q.metadata['nextKey'] as int;

        // Find the current key in the fourths order.
        final currentIndex =
            fourths.indexWhere((pc) => pc.value == currentKeyValue);
        expect(currentIndex, isNot(-1),
            reason: 'Current key $currentKeyValue should be in fourths order');

        // The next key should be one step ahead in the circle of fourths.
        final expectedNext = fourths[(currentIndex + 1) % 12];
        expect(nextKeyValue, expectedNext.value,
            reason:
                'After ${NoteName.toFlat(PitchClass(currentKeyValue))} should be '
                '${NoteName.toFlat(expectedNext)}, got '
                '${NoteName.toFlat(PitchClass(nextKeyValue))}');

        // The expected answer string should match the flat name of the next key.
        expect(q.expectedAnswer, NoteName.toFlat(PitchClass(nextKeyValue)));
      }
    });

    test('MCQ options include the correct answer', () {
      final questions = generator.generate(exercise, count: 20);

      for (final q in questions) {
        expect(q.multipleChoiceOptions, isNotNull);
        expect(q.multipleChoiceOptions!.length, 4);
        expect(q.multipleChoiceOptions!, contains(q.expectedAnswer));
      }
    });

    test('defaults to nextKey mode when subMode is absent', () {
      final defaultExercise = Exercise(
        id: 'test-cof-default',
        title: 'Circle of Fourths',
        mode: ExerciseMode.drill,
        inputType: InputType.multipleChoice,
        generatorId: 'circleOfFourths',
      );

      final questions = generator.generate(defaultExercise, count: 3);
      for (final q in questions) {
        expect(q.multipleChoiceOptions, isNotNull);
        expect(q.multipleChoiceOptions!.length, 4);
      }
    });
  });

  group('CircleOfFourthsGenerator - playChord mode', () {
    final exercise = Exercise(
      id: 'test-cof-play',
      title: 'Circle of Fourths Play',
      mode: ExerciseMode.drill,
      inputType: InputType.piano,
      generatorId: 'circleOfFourths',
      config: {'subMode': 'playChord', 'chordQuality': 'Major'},
    );

    test('generates the requested number of questions', () {
      final questions = generator.generate(exercise, count: 7);
      expect(questions.length, 7);
    });

    test('expected answers are valid PitchClass sets for the chord', () {
      final questions = generator.generate(exercise, count: 20);

      for (final q in questions) {
        final expected = q.expectedAnswer as Set<PitchClass>;
        expect(expected, isNotEmpty);

        // Every element should have a valid pitch class value 0..11.
        for (final pc in expected) {
          expect(pc.value, inInclusiveRange(0, 11));
        }

        // Rebuild the chord from metadata and verify the answer matches.
        final root = PitchClass(q.metadata['root'] as int);
        final qualityName = q.metadata['quality'] as String;
        final quality = ChordQuality.allQualities
            .firstWhere((cq) => cq.name == qualityName);
        final rebuilt = quality.build(root).toSet();
        expect(expected, rebuilt);
      }
    });

    test('playChord prompt includes root note and quality symbol', () {
      final questions = generator.generate(exercise, count: 10);

      for (final q in questions) {
        final root = PitchClass(q.metadata['root'] as int);
        final rootName = NoteName.toFlat(root);
        expect(q.promptText, contains(rootName));
        expect(q.promptText, startsWith('Play '));
      }
    });
  });
}
