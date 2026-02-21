import 'dart:math';

import '../../../core/music/chord_quality.dart';
import '../../../core/music/note_name.dart';
import '../../../core/music/pitch_class.dart';
import '../../../core/widgets/notation/notation_renderer.dart';
import '../../../domain/models/exercise.dart';
import '../runner/exercise_question.dart';
import '../runner/question_generator.dart';

/// Generates "play X chord" questions using [ChordQuality.build].
///
/// Configuration via `exercise.config`:
/// - `qualities` (`List<String>?`): Names of chord qualities to use.
///   Defaults to all qualities in [ChordQuality.allQualities].
/// - `roots` (`List<int>?`): Pitch-class values to use as roots.
///   Defaults to all 12 pitch classes.
class ChordBuildGenerator extends QuestionGenerator {
  @override
  List<ExerciseQuestion> generate(Exercise exercise, {int count = 10}) {
    final random = Random();

    // Resolve which qualities to drill.
    final qualityNames = (exercise.config['qualities'] as List<dynamic>?)
        ?.cast<String>();
    final qualities = qualityNames != null
        ? ChordQuality.allQualities
            .where((q) =>
                qualityNames.any((n) => n.toLowerCase() == q.name.toLowerCase()))
            .toList()
        : List<ChordQuality>.from(ChordQuality.allQualities);

    if (qualities.isEmpty) {
      throw ArgumentError('No matching chord qualities found in config');
    }

    // Resolve which roots to drill.
    final rootValues = (exercise.config['roots'] as List<dynamic>?)
        ?.cast<int>();
    final roots = rootValues != null
        ? rootValues.map((v) => PitchClass(v)).toList()
        : List.generate(12, (i) => PitchClass(i));

    final questions = <ExerciseQuestion>[];

    for (var i = 0; i < count; i++) {
      final quality = qualities[random.nextInt(qualities.length)];
      final root = roots[random.nextInt(roots.length)];
      final chordTones = quality.build(root);
      final expected = chordTones.toSet();
      final rootName = NoteName.toSharp(root);

      questions.add(ExerciseQuestion(
        promptText: 'Play $rootName${quality.symbol}',
        notationData: NotationData(
          pitches: chordTones,
          label: '$rootName${quality.symbol}',
        ),
        expectedAnswer: expected,
        metadata: {
          'root': root.value,
          'quality': quality.name,
          'chordTones': chordTones.map((pc) => pc.value).toList(),
        },
      ));
    }

    return questions;
  }
}
