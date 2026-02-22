import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/core/music/chord_quality.dart';
import 'package:jazz_piano_tools/core/music/note_name.dart';
import 'package:jazz_piano_tools/core/music/pitch_class.dart';
import 'package:jazz_piano_tools/domain/enums/exercise_mode.dart';
import 'package:jazz_piano_tools/domain/enums/input_type.dart';
import 'package:jazz_piano_tools/domain/models/exercise.dart';
import 'package:jazz_piano_tools/features/drill/generators/guide_tone_generator.dart';

void main() {
  final generator = GuideToneGenerator();

  group('GuideToneGenerator', () {
    final exercise = Exercise(
      id: 'test-guide-tone',
      title: 'Guide Tones',
      mode: ExerciseMode.test,
      inputType: InputType.multipleChoice,
      generatorId: 'guideTone',
    );

    test('generates the requested number of questions', () {
      final questions3 = generator.generate(exercise, count: 3);
      expect(questions3.length, 3);

      final questions12 = generator.generate(exercise, count: 12);
      expect(questions12.length, 12);

      final questions1 = generator.generate(exercise, count: 1);
      expect(questions1.length, 1);
    });

    test('expected answers are musically correct guide tones', () {
      final questions = generator.generate(exercise, count: 50);

      for (final q in questions) {
        final rootValue = q.metadata['root'] as int;
        final qualityName = q.metadata['quality'] as String;
        final guideToneValues =
            (q.metadata['guideTones'] as List).cast<int>();

        final root = PitchClass(rootValue);
        final quality = ChordQuality.allQualities
            .firstWhere((cq) => cq.name == qualityName);

        // Compute expected guide tones using the static helper.
        final expectedGuides = GuideToneGenerator.guideTones(root, quality);
        final expectedValues =
            expectedGuides.map((pc) => pc.value).toList();
        expect(guideToneValues, expectedValues);

        // The answer string should be the flat names joined with " & ".
        final expectedAnswer =
            expectedGuides.map((pc) => NoteName.toFlat(pc)).join(' & ');
        expect(q.expectedAnswer, expectedAnswer);
      }
    });

    test('MCQ options include the correct answer', () {
      final questions = generator.generate(exercise, count: 30);

      for (final q in questions) {
        expect(q.multipleChoiceOptions, isNotNull);
        expect(q.multipleChoiceOptions!.length, 4);
        expect(q.multipleChoiceOptions!, contains(q.expectedAnswer));
      }
    });

    test('prompt text includes root name and quality symbol', () {
      final questions = generator.generate(exercise, count: 10);

      for (final q in questions) {
        final root = PitchClass(q.metadata['root'] as int);
        final rootName = NoteName.toFlat(root);
        expect(q.promptText, contains(rootName));
        expect(q.promptText, contains('guide tones'));
      }
    });
  });

  group('GuideToneGenerator - known answers', () {
    test('C dominant 7 guide tones are E & Bb', () {
      final guides =
          GuideToneGenerator.guideTones(PitchClass.c, ChordQuality.dominant7);
      // C7 = C, E, G, Bb -> 3rd = E (4), 7th = Bb (10)
      expect(guides.length, 2);
      expect(guides[0].value, 4); // E
      expect(guides[1].value, 10); // Bb
    });

    test('C major 7 guide tones are E & B', () {
      final guides =
          GuideToneGenerator.guideTones(PitchClass.c, ChordQuality.major7);
      // Cmaj7 = C, E, G, B -> 3rd = E (4), 7th = B (11)
      expect(guides.length, 2);
      expect(guides[0].value, 4); // E
      expect(guides[1].value, 11); // B
    });

    test('D minor 7 guide tones are F & C', () {
      final guides =
          GuideToneGenerator.guideTones(PitchClass.d, ChordQuality.minor7);
      // Dm7 = D, F, A, C -> 3rd = F (5), 7th = C (0)
      expect(guides.length, 2);
      expect(guides[0].value, 5); // F
      expect(guides[1].value, 0); // C
    });

    test('triad without 7th returns only the 3rd', () {
      final guides =
          GuideToneGenerator.guideTones(PitchClass.c, ChordQuality.major);
      // C major triad = C, E, G -> only 3 notes, guide tone is just the 3rd
      expect(guides.length, 1);
      expect(guides[0].value, 4); // E
    });
  });

  group('GuideToneGenerator - itemGroups', () {
    test('default config has 3 groups by quality with 12 items each', () {
      final exercise = Exercise(
        id: 'test-guide-tone',
        title: 'Guide Tones',
        mode: ExerciseMode.test,
        inputType: InputType.multipleChoice,
        generatorId: 'guideTone',
      );

      final groups = generator.itemGroups(exercise);
      expect(groups.length, 3);
      expect(groups.keys,
          containsAll(['Dominant 7th', 'Major 7th', 'Minor 7th']));
      for (final entry in groups.entries) {
        expect(entry.value.length, 12,
            reason: '${entry.key} group should have 12 items');
      }
    });
  });

  group('GuideToneGenerator with filtered config', () {
    test('respects qualities filter', () {
      final exercise = Exercise(
        id: 'test-guide-filtered',
        title: 'Filtered Guide Tones',
        mode: ExerciseMode.test,
        inputType: InputType.multipleChoice,
        generatorId: 'guideTone',
        config: {
          'qualities': ['Dominant 7th'],
        },
      );

      final questions = generator.generate(exercise, count: 20);

      for (final q in questions) {
        expect(q.metadata['quality'], 'Dominant 7th');
      }
    });

    test('respects roots filter', () {
      final exercise = Exercise(
        id: 'test-guide-roots',
        title: 'Filtered Roots',
        mode: ExerciseMode.test,
        inputType: InputType.multipleChoice,
        generatorId: 'guideTone',
        config: {
          'roots': [0, 2], // C and D only
        },
      );

      final questions = generator.generate(exercise, count: 20);

      for (final q in questions) {
        final rootValue = q.metadata['root'] as int;
        expect(rootValue, anyOf(0, 2));
      }
    });

    test('throws on invalid quality names', () {
      final exercise = Exercise(
        id: 'test-guide-invalid',
        title: 'Invalid',
        mode: ExerciseMode.test,
        inputType: InputType.multipleChoice,
        generatorId: 'guideTone',
        config: {
          'qualities': ['FakeQuality'],
        },
      );

      expect(
        () => generator.generate(exercise, count: 1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
