import 'dart:math';

import '../../../core/music/interval.dart';
import '../../../core/music/note_name.dart';
import '../../../core/music/pitch_class.dart';
import '../../../core/widgets/notation/notation_renderer.dart';
import '../../../domain/models/exercise.dart';
import '../runner/exercise_question.dart';
import '../runner/question_generator.dart';

/// Generates "play the interval above a given note" questions.
///
/// Configuration via `exercise.config`:
/// - `intervals` (`List<int>?`): Semitone values of intervals to drill.
///   Defaults to all 12 intervals.
/// - `roots` (`List<int>?`): Pitch-class values for the starting note.
///   Defaults to all 12 pitch classes.
class IntervalBuildGenerator extends QuestionGenerator {
  @override
  List<ExerciseQuestion> generate(Exercise exercise, {int count = 10}) {
    final random = Random();

    // Resolve which intervals to drill.
    final intervalValues =
        (exercise.config['intervals'] as List<dynamic>?)?.cast<int>();
    final intervals = intervalValues != null
        ? intervalValues
            .map((v) => Interval.values[v % 12])
            .toList()
        : Interval.values.where((i) => i != Interval.unison).toList();

    // Resolve which roots to use.
    final rootValues =
        (exercise.config['roots'] as List<dynamic>?)?.cast<int>();
    final roots = rootValues != null
        ? rootValues.map((v) => PitchClass(v)).toList()
        : List.generate(12, (i) => PitchClass(i));

    final questions = <ExerciseQuestion>[];

    for (var i = 0; i < count; i++) {
      final interval = intervals[random.nextInt(intervals.length)];
      final root = roots[random.nextInt(roots.length)];
      final target = root.transpose(interval.semitones);
      final rootName = NoteName.toSharp(root);
      final targetName = NoteName.toSharp(target);

      // The expected answer is a set containing only the target pitch class.
      final expected = <PitchClass>{target};

      questions.add(ExerciseQuestion(
        promptText:
            'Play a ${interval.fullName} above $rootName',
        notationData: NotationData(
          pitches: [root, target],
          label: '$rootName + ${interval.symbol} = $targetName',
        ),
        expectedAnswer: expected,
        metadata: {
          'root': root.value,
          'interval': interval.semitones,
          'intervalName': interval.fullName,
          'target': target.value,
        },
      ));
    }

    return questions;
  }
}
