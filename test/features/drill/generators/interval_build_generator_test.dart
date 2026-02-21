import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/core/music/interval.dart' as music;
import 'package:jazz_piano_tools/core/music/note_name.dart';
import 'package:jazz_piano_tools/core/music/pitch_class.dart';
import 'package:jazz_piano_tools/domain/enums/exercise_mode.dart';
import 'package:jazz_piano_tools/domain/enums/input_type.dart';
import 'package:jazz_piano_tools/domain/models/exercise.dart';
import 'package:jazz_piano_tools/features/drill/generators/interval_build_generator.dart';

void main() {
  final generator = IntervalBuildGenerator();

  group('IntervalBuildGenerator', () {
    final exercise = Exercise(
      id: 'test-interval-build',
      title: 'Build Intervals',
      mode: ExerciseMode.drill,
      inputType: InputType.piano,
      generatorId: 'intervalBuild',
    );

    test('generates the requested number of questions', () {
      final questions4 = generator.generate(exercise, count: 4);
      expect(questions4.length, 4);

      final questions20 = generator.generate(exercise, count: 20);
      expect(questions20.length, 20);

      final questions1 = generator.generate(exercise, count: 1);
      expect(questions1.length, 1);
    });

    test('expected answer is the correct pitch class for the interval', () {
      final questions = generator.generate(exercise, count: 50);

      for (final q in questions) {
        final expected = q.expectedAnswer as Set<PitchClass>;

        // Interval questions expect exactly one target pitch class.
        expect(expected.length, 1);

        final rootValue = q.metadata['root'] as int;
        final intervalSemitones = q.metadata['interval'] as int;
        final targetValue = q.metadata['target'] as int;

        // The target should be root + interval (mod 12).
        expect(targetValue, (rootValue + intervalSemitones) % 12,
            reason:
                'Root $rootValue + interval $intervalSemitones should give '
                '${(rootValue + intervalSemitones) % 12}, got $targetValue');

        // The expected set should contain exactly the target.
        expect(expected.first.value, targetValue);
      }
    });

    test('piano questions have valid PitchClass sets', () {
      final questions = generator.generate(exercise, count: 30);

      for (final q in questions) {
        final expected = q.expectedAnswer as Set<PitchClass>;
        for (final pc in expected) {
          expect(pc.value, inInclusiveRange(0, 11));
        }

        // Notation data should contain both root and target.
        expect(q.notationData, isNotNull);
        expect(q.notationData!.pitches.length, 2);
      }
    });

    test('default config excludes unison', () {
      // By default, unison (0 semitones) should not appear.
      final questions = generator.generate(exercise, count: 100);

      for (final q in questions) {
        final intervalSemitones = q.metadata['interval'] as int;
        expect(intervalSemitones, isNot(0),
            reason: 'Default config should not include unison');
      }
    });

    test('prompt text contains interval name and root note', () {
      final questions = generator.generate(exercise, count: 10);

      for (final q in questions) {
        final root = PitchClass(q.metadata['root'] as int);
        final rootName = NoteName.toSharp(root);
        final intervalName = q.metadata['intervalName'] as String;
        expect(q.promptText, contains(rootName));
        expect(q.promptText, contains(intervalName));
        expect(q.promptText, startsWith('Play a'));
      }
    });
  });

  group('IntervalBuildGenerator with filtered config', () {
    test('respects intervals filter', () {
      final exercise = Exercise(
        id: 'test-interval-filtered',
        title: 'Filtered Intervals',
        mode: ExerciseMode.drill,
        inputType: InputType.piano,
        generatorId: 'intervalBuild',
        config: {
          'intervals': [3, 7], // minor 3rd and perfect 5th
        },
      );

      final questions = generator.generate(exercise, count: 30);

      for (final q in questions) {
        final intervalSemitones = q.metadata['interval'] as int;
        expect(intervalSemitones, anyOf(3, 7));
      }
    });

    test('respects roots filter', () {
      final exercise = Exercise(
        id: 'test-interval-roots',
        title: 'Filtered Roots',
        mode: ExerciseMode.drill,
        inputType: InputType.piano,
        generatorId: 'intervalBuild',
        config: {
          'roots': [0, 4, 9], // C, E, A only
        },
      );

      final questions = generator.generate(exercise, count: 30);

      for (final q in questions) {
        final rootValue = q.metadata['root'] as int;
        expect(rootValue, anyOf(0, 4, 9));
      }
    });

    test('specific interval and root produces known answer', () {
      // Fix to only C root and only perfect 5th (7 semitones).
      final exercise = Exercise(
        id: 'test-interval-specific',
        title: 'Specific Interval',
        mode: ExerciseMode.drill,
        inputType: InputType.piano,
        generatorId: 'intervalBuild',
        config: {
          'intervals': [7],
          'roots': [0],
        },
      );

      final questions = generator.generate(exercise, count: 5);

      for (final q in questions) {
        // C + P5 = G (pitch class 7).
        final expected = q.expectedAnswer as Set<PitchClass>;
        expect(expected.length, 1);
        expect(expected.first.value, 7);
        expect(q.metadata['target'], 7);
      }
    });
  });
}
