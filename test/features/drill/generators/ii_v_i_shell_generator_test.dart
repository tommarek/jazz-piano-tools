import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/core/music/pitch_class.dart';
import 'package:jazz_piano_tools/domain/enums/exercise_mode.dart';
import 'package:jazz_piano_tools/domain/enums/input_type.dart';
import 'package:jazz_piano_tools/domain/models/exercise.dart';
import 'package:jazz_piano_tools/features/drill/generators/ii_v_i_shell_generator.dart';

void main() {
  final generator = IiViShellGenerator();

  group('IiViShellGenerator', () {
    final exercise = Exercise(
      id: 'test-ii-v-i',
      title: 'ii-V-I Shells',
      mode: ExerciseMode.test,
      inputType: InputType.piano,
      generatorId: 'iiViShell',
    );

    test('generates the requested number of questions', () {
      final questions5 = generator.generate(exercise, count: 5);
      expect(questions5.length, 5);

      final questions10 = generator.generate(exercise, count: 10);
      expect(questions10.length, 10);

      final questions1 = generator.generate(exercise, count: 1);
      expect(questions1.length, 1);
    });

    test('expected answers are musically correct shell voicings', () {
      // Shell voicing intervals from chord root:
      //   ii (minor 7):    root, m3 (+3), m7 (+10)
      //   V  (dominant 7): root, M3 (+4), m7 (+10)
      //   I  (major 7):    root, M3 (+4), M7 (+11)
      const shellIntervals = {
        'ii': [0, 3, 10],
        'V': [0, 4, 10],
        'I': [0, 4, 11],
      };
      // Root offsets from key centre:
      //   ii = +2, V = +7, I = +0
      const rootOffsets = {'ii': 2, 'V': 7, 'I': 0};

      final questions = generator.generate(exercise, count: 50);

      for (final q in questions) {
        final expected = q.expectedAnswer as Set<PitchClass>;
        expect(expected.length, 3,
            reason: 'Shell voicings always have 3 notes (root, 3rd, 7th)');

        final keyValue = q.metadata['key'] as int;
        final chordLabel = q.metadata['chordLabel'] as String;
        final chordRootValue = q.metadata['chordRoot'] as int;

        // Verify chord root offset from key.
        final expectedChordRoot =
            (keyValue + rootOffsets[chordLabel]!) % 12;
        expect(chordRootValue, expectedChordRoot,
            reason:
                '$chordLabel chord root should be $expectedChordRoot in key $keyValue');

        // Verify shell pitch classes.
        final intervals = shellIntervals[chordLabel]!;
        final expectedPitches =
            intervals.map((s) => PitchClass(chordRootValue + s)).toSet();
        expect(expected, expectedPitches,
            reason:
                '$chordLabel shell in key $keyValue should be $expectedPitches');
      }
    });

    test('piano questions have valid PitchClass sets', () {
      final questions = generator.generate(exercise, count: 20);

      for (final q in questions) {
        final expected = q.expectedAnswer as Set<PitchClass>;
        for (final pc in expected) {
          expect(pc.value, inInclusiveRange(0, 11));
        }

        // Should have notation data.
        expect(q.notationData, isNotNull);
        expect(q.notationData!.pitches.length, 3);
      }
    });

    test('prompt text includes chord label and key name', () {
      final questions = generator.generate(exercise, count: 10);

      for (final q in questions) {
        final chordLabel = q.metadata['chordLabel'] as String;
        expect(q.promptText, contains(chordLabel));
        expect(q.promptText, contains('shell voicing'));
        expect(q.promptText, contains('key of'));
      }
    });
  });

  group('IiViShellGenerator - key of C verified', () {
    test('ii shell in C is Dm7 shell: D, F, C', () {
      final exercise = Exercise(
        id: 'test-ii-v-i-c',
        title: 'ii-V-I in C',
        mode: ExerciseMode.test,
        inputType: InputType.piano,
        generatorId: 'iiViShell',
        config: {
          'keys': [0], // C only
          'chordIndex': 0, // ii only
        },
      );

      final questions = generator.generate(exercise, count: 5);

      for (final q in questions) {
        final expected = q.expectedAnswer as Set<PitchClass>;
        // ii in C: chord root = D (2), shell = D(2), F(5), C(0)
        expect(expected, {PitchClass(2), PitchClass(5), PitchClass(0)});
      }
    });

    test('V shell in C is G7 shell: G, B, F', () {
      final exercise = Exercise(
        id: 'test-v-c',
        title: 'V in C',
        mode: ExerciseMode.test,
        inputType: InputType.piano,
        generatorId: 'iiViShell',
        config: {
          'keys': [0],
          'chordIndex': 1, // V only
        },
      );

      final questions = generator.generate(exercise, count: 5);

      for (final q in questions) {
        final expected = q.expectedAnswer as Set<PitchClass>;
        // V in C: chord root = G (7), shell = G(7), B(11), F(5)
        expect(expected, {PitchClass(7), PitchClass(11), PitchClass(5)});
      }
    });

    test('I shell in C is Cmaj7 shell: C, E, B', () {
      final exercise = Exercise(
        id: 'test-i-c',
        title: 'I in C',
        mode: ExerciseMode.test,
        inputType: InputType.piano,
        generatorId: 'iiViShell',
        config: {
          'keys': [0],
          'chordIndex': 2, // I only
        },
      );

      final questions = generator.generate(exercise, count: 5);

      for (final q in questions) {
        final expected = q.expectedAnswer as Set<PitchClass>;
        // I in C: chord root = C (0), shell = C(0), E(4), B(11)
        expect(expected, {PitchClass(0), PitchClass(4), PitchClass(11)});
      }
    });
  });

  group('IiViShellGenerator - itemGroups', () {
    test('default config has 3 groups (ii, V, I) with 12 items each', () {
      final exercise = Exercise(
        id: 'test-ii-v-i',
        title: 'ii-V-I Shells',
        mode: ExerciseMode.test,
        inputType: InputType.piano,
        generatorId: 'iiViShell',
      );

      final groups = generator.itemGroups(exercise);
      expect(groups.length, 3);
      expect(groups.keys, containsAll(['ii', 'V', 'I']));
      for (final entry in groups.entries) {
        expect(entry.value.length, 12,
            reason: '${entry.key} group should have 12 items');
        for (final id in entry.value) {
          expect(id, startsWith('${entry.key}-'));
        }
      }
    });

    test('chordIndex config limits to single group', () {
      final exercise = Exercise(
        id: 'test-ii-v-i-v',
        title: 'V only',
        mode: ExerciseMode.test,
        inputType: InputType.piano,
        generatorId: 'iiViShell',
        config: {'chordIndex': 1},
      );

      final groups = generator.itemGroups(exercise);
      expect(groups.length, 1);
      expect(groups.keys.first, 'V');
      expect(groups['V']!.length, 12);
    });
  });

  group('IiViShellGenerator with filtered config', () {
    test('respects keys filter', () {
      final exercise = Exercise(
        id: 'test-ii-v-i-keys',
        title: 'Filtered Keys',
        mode: ExerciseMode.test,
        inputType: InputType.piano,
        generatorId: 'iiViShell',
        config: {
          'keys': [0, 5], // C and F only
        },
      );

      final questions = generator.generate(exercise, count: 20);

      for (final q in questions) {
        final keyValue = q.metadata['key'] as int;
        expect(keyValue, anyOf(0, 5));
      }
    });

    test('respects chordIndex filter', () {
      final exercise = Exercise(
        id: 'test-ii-v-i-chord',
        title: 'V only',
        mode: ExerciseMode.test,
        inputType: InputType.piano,
        generatorId: 'iiViShell',
        config: {
          'chordIndex': 1, // V only
        },
      );

      final questions = generator.generate(exercise, count: 20);

      for (final q in questions) {
        expect(q.metadata['chordLabel'], 'V');
      }
    });
  });
}
