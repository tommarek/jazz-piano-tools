import 'dart:math';

import '../../../core/music/circle_of_fifths.dart';
import '../../../core/music/note_name.dart';
import '../../../core/music/pitch_class.dart';
import '../../../core/music/chord_quality.dart';
import '../../../core/widgets/notation/notation_renderer.dart';
import '../../../domain/models/exercise.dart';
import '../runner/exercise_question.dart';
import '../runner/question_generator.dart';

/// Generates circle-of-fourths questions.
///
/// Supports two modes controlled by `exercise.config['subMode']`:
///
/// - `'nextKey'` (default): Multiple-choice — "What key comes after X
///   in the circle of fourths?" with 4 options.
/// - `'playChord'`: Piano input — "Play the Y chord in the key of X"
///   where Y is drawn from the exercise config (`chordQuality`, defaults
///   to major).
class CircleOfFourthsGenerator extends QuestionGenerator {
  @override
  List<ExerciseQuestion> generate(Exercise exercise, {int count = 10}) {
    final random = Random();
    final fourths = CircleOfFifths.fourthsOrder;
    final subMode = exercise.config['subMode'] as String? ?? 'nextKey';

    if (subMode == 'playChord') {
      return _generatePlayChordQuestions(exercise, fourths, random, count);
    }
    return _generateNextKeyQuestions(fourths, random, count);
  }

  List<ExerciseQuestion> _generateNextKeyQuestions(
    List<PitchClass> fourths,
    Random random,
    int count,
  ) {
    final questions = <ExerciseQuestion>[];

    for (var i = 0; i < count; i++) {
      final index = random.nextInt(12);
      final currentKey = fourths[index];
      final nextKey = fourths[(index + 1) % 12];

      final correctName = NoteName.toFlat(nextKey);

      // Build 4 options including the correct answer.
      final options = <String>{correctName};
      while (options.length < 4) {
        final randPc = PitchClass(random.nextInt(12));
        final name = NoteName.toFlat(randPc);
        if (name != correctName) {
          options.add(name);
        }
      }

      final shuffled = options.toList()..shuffle(random);

      questions.add(ExerciseQuestion(
        promptText:
            'What key comes after ${NoteName.toFlat(currentKey)} in the circle of fourths?',
        expectedAnswer: correctName,
        multipleChoiceOptions: shuffled,
        metadata: {
          'currentKey': currentKey.value,
          'nextKey': nextKey.value,
        },
      ));
    }

    return questions;
  }

  List<ExerciseQuestion> _generatePlayChordQuestions(
    Exercise exercise,
    List<PitchClass> fourths,
    Random random,
    int count,
  ) {
    final qualityName =
        exercise.config['chordQuality'] as String? ?? 'Major';
    final quality = ChordQuality.allQualities.firstWhere(
      (q) => q.name.toLowerCase() == qualityName.toLowerCase(),
      orElse: () => ChordQuality.major,
    );

    final questions = <ExerciseQuestion>[];

    for (var i = 0; i < count; i++) {
      final index = random.nextInt(12);
      final root = fourths[index];
      final chordTones = quality.build(root);
      final expectedPitchClasses = chordTones.toSet();
      final rootName = NoteName.toFlat(root);

      questions.add(ExerciseQuestion(
        promptText: 'Play $rootName${quality.symbol}',
        notationData: NotationData(
          pitches: chordTones,
          label: '$rootName${quality.symbol}',
        ),
        expectedAnswer: expectedPitchClasses,
        metadata: {
          'root': root.value,
          'quality': quality.name,
        },
      ));
    }

    return questions;
  }
}
