import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/core/music/chord_quality.dart';
import 'package:jazz_piano_tools/core/music/note_name.dart';
import 'package:jazz_piano_tools/core/music/pitch_class.dart';
import 'package:jazz_piano_tools/domain/enums/exercise_mode.dart';
import 'package:jazz_piano_tools/domain/enums/input_type.dart';
import 'package:jazz_piano_tools/domain/models/exercise.dart';
import 'package:jazz_piano_tools/features/drill/generators/chord_build_generator.dart';

void main() {
  final generator = ChordBuildGenerator();

  group('ChordBuildGenerator', () {
    final exercise = Exercise(
      id: 'test-chord-build',
      title: 'Build Chords',
      mode: ExerciseMode.drill,
      inputType: InputType.piano,
      generatorId: 'chordBuild',
    );

    test('generates the requested number of questions', () {
      final questions3 = generator.generate(exercise, count: 3);
      expect(questions3.length, 3);

      final questions15 = generator.generate(exercise, count: 15);
      expect(questions15.length, 15);

      final questions1 = generator.generate(exercise, count: 1);
      expect(questions1.length, 1);
    });

    test('expected answers are valid PitchClass sets matching the chord', () {
      final questions = generator.generate(exercise, count: 30);

      for (final q in questions) {
        final expected = q.expectedAnswer as Set<PitchClass>;
        expect(expected, isNotEmpty);

        // Every element should be a valid pitch class.
        for (final pc in expected) {
          expect(pc.value, inInclusiveRange(0, 11));
        }

        // Rebuild from metadata and verify.
        final root = PitchClass(q.metadata['root'] as int);
        final qualityName = q.metadata['quality'] as String;
        final quality = ChordQuality.allQualities
            .firstWhere((cq) => cq.name == qualityName);
        final rebuilt = quality.build(root).toSet();
        expect(expected, rebuilt);

        // Also verify the chordTones metadata is consistent.
        final chordToneValues =
            (q.metadata['chordTones'] as List).cast<int>();
        final chordTonePcs = chordToneValues.map((v) => PitchClass(v)).toSet();
        expect(expected, chordTonePcs);
      }
    });

    test('prompt text includes root name and quality symbol', () {
      final questions = generator.generate(exercise, count: 20);

      for (final q in questions) {
        final root = PitchClass(q.metadata['root'] as int);
        final rootName = NoteName.toSharp(root);
        expect(q.promptText, contains(rootName));
        expect(q.promptText, startsWith('Play '));
      }
    });

    test('has notation data for every question', () {
      final questions = generator.generate(exercise, count: 10);

      for (final q in questions) {
        expect(q.notationData, isNotNull);
        expect(q.notationData!.pitches, isNotEmpty);
      }
    });
  });

  group('ChordBuildGenerator with filtered config', () {
    test('respects qualities filter', () {
      final exercise = Exercise(
        id: 'test-chord-filtered',
        title: 'Build Chords Filtered',
        mode: ExerciseMode.drill,
        inputType: InputType.piano,
        generatorId: 'chordBuild',
        config: {
          'qualities': ['Major', 'Minor'],
        },
      );

      final questions = generator.generate(exercise, count: 30);

      for (final q in questions) {
        final qualityName = q.metadata['quality'] as String;
        expect(qualityName, anyOf('Major', 'Minor'));
      }
    });

    test('respects roots filter', () {
      final exercise = Exercise(
        id: 'test-chord-roots',
        title: 'Build Chords Roots',
        mode: ExerciseMode.drill,
        inputType: InputType.piano,
        generatorId: 'chordBuild',
        config: {
          'roots': [0, 7], // C and G only
        },
      );

      final questions = generator.generate(exercise, count: 20);

      for (final q in questions) {
        final rootValue = q.metadata['root'] as int;
        expect(rootValue, anyOf(0, 7));
      }
    });

    test('throws on invalid quality names', () {
      final exercise = Exercise(
        id: 'test-chord-invalid',
        title: 'Invalid',
        mode: ExerciseMode.drill,
        inputType: InputType.piano,
        generatorId: 'chordBuild',
        config: {
          'qualities': ['NotARealQuality'],
        },
      );

      expect(
        () => generator.generate(exercise, count: 1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
