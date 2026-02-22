import 'package:flutter_test/flutter_test.dart';

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
      mode: ExerciseMode.test,
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
        final rootNamer = NoteName.namerForRoot(root);
        final rootName = rootNamer(root);
        final intervalName = q.metadata['intervalName'] as String;
        expect(q.promptText, contains(rootName));
        expect(q.promptText, contains(intervalName));
        expect(q.promptText, startsWith('Play a'));
      }
    });

    test('metadata itemId is key-specific (interval:root format)', () {
      final questions = generator.generate(exercise, count: 20);

      for (final q in questions) {
        final itemId = q.metadata['itemId'] as String;
        expect(itemId, contains(':'),
            reason: 'itemId should be in "interval:root" format');
        final parts = itemId.split(':');
        expect(parts.length, 2);
        // First part is the interval name
        expect(q.metadata['intervalName'], parts[0]);
        // Second part is the flat root name
        final root = PitchClass(q.metadata['root'] as int);
        expect(parts[1], NoteName.toFlat(root));
      }
    });
  });

  group('IntervalBuildGenerator - allItemIds and itemGroups', () {
    final exercise = Exercise(
      id: 'test-interval-build',
      title: 'Build Intervals',
      mode: ExerciseMode.test,
      inputType: InputType.piano,
      generatorId: 'intervalBuild',
    );

    test('allItemIds returns key-specific IDs (11 intervals x 12 keys)', () {
      final ids = generator.allItemIds(exercise);
      // 11 intervals (no unison) x 12 keys = 132
      expect(ids.length, 132);
      expect(ids.toSet().length, 132, reason: 'All IDs should be unique');

      // Verify format
      for (final id in ids) {
        expect(id, contains(':'));
      }

      // Verify specific examples
      expect(ids, contains('Minor 2nd:C'));
      expect(ids, contains('Major 7th:B'));
      expect(ids, contains('Perfect 5th:Gb'));
    });

    test('itemGroups returns 11 groups with 12 items each', () {
      final groups = generator.itemGroups(exercise);
      expect(groups.length, 11);
      for (final entry in groups.entries) {
        expect(entry.value.length, 12,
            reason: '${entry.key} should have 12 items');
        // All items in group should start with the group name
        for (final id in entry.value) {
          expect(id, startsWith('${entry.key}:'));
        }
      }
    });

    test('allItemIds with filtered config', () {
      final filtered = Exercise(
        id: 'test-filtered',
        title: 'Filtered',
        mode: ExerciseMode.test,
        inputType: InputType.piano,
        generatorId: 'intervalBuild',
        config: {
          'intervals': [3, 7], // minor 3rd and perfect 5th
          'roots': [0, 4, 9], // C, E, A only
        },
      );

      final ids = generator.allItemIds(filtered);
      expect(ids.length, 6); // 2 intervals x 3 roots
      expect(ids, contains('Minor 3rd:C'));
      expect(ids, contains('Perfect 5th:A'));
    });
  });

  group('IntervalBuildGenerator - generateForItems with key-specific IDs', () {
    final exercise = Exercise(
      id: 'test-interval-build',
      title: 'Build Intervals',
      mode: ExerciseMode.test,
      inputType: InputType.piano,
      generatorId: 'intervalBuild',
    );

    test('generates questions for specific interval:root combos', () {
      final questions = generator.generateForItems(
          exercise, ['Perfect 5th:C', 'Minor 3rd:Eb']);

      expect(questions.length, 2);

      // First question: P5 above C = G
      final q1 = questions[0];
      expect(q1.metadata['intervalName'], 'Perfect 5th');
      expect(q1.metadata['root'], 0); // C
      expect(q1.metadata['target'], 7); // G

      // Second question: m3 above Eb = Gb
      final q2 = questions[1];
      expect(q2.metadata['intervalName'], 'Minor 3rd');
      expect(q2.metadata['root'], 3); // Eb
      expect(q2.metadata['target'], 6); // Gb
    });
  });

  group('IntervalBuildGenerator with filtered config', () {
    test('respects intervals filter', () {
      final exercise = Exercise(
        id: 'test-interval-filtered',
        title: 'Filtered Intervals',
        mode: ExerciseMode.test,
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
        mode: ExerciseMode.test,
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
        mode: ExerciseMode.test,
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
