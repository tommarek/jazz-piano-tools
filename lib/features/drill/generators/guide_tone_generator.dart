import 'dart:math';

import '../../../core/music/chord_quality.dart';
import '../../../core/music/note_name.dart';
import '../../../core/music/pitch_class.dart';
import '../../../domain/models/exercise.dart';
import '../runner/exercise_question.dart';
import '../runner/question_generator.dart';

/// Generates guide-tone identification multiple-choice questions.
///
/// Guide tones are the 3rd and 7th of a chord — the notes that define
/// its quality and drive voice leading. This generator asks the user to
/// identify the guide tones of a given chord.
///
/// Configuration via `exercise.config`:
/// - `qualities` (`List<String>?`): Chord quality names to include.
///   Defaults to [dominant7, major7, minor7].
/// - `roots` (`List<int>?`): Pitch-class values for chord roots.
///   Defaults to all 12 pitch classes.
class GuideToneGenerator extends QuestionGenerator {
  /// Returns the 3rd and 7th of a chord as a pair of [PitchClass].
  static List<PitchClass> guideTones(PitchClass root, ChordQuality quality) {
    final tones = quality.build(root);
    // tones[0] = root, tones[1] = 3rd, tones[2] = 5th, tones[3] = 7th
    if (tones.length < 4) {
      // For triads without a 7th, the guide tone is just the 3rd.
      return [tones[1]];
    }
    return [tones[1], tones[3]];
  }

  static const _defaultQualities = [
    ChordQuality.dominant7,
    ChordQuality.major7,
    ChordQuality.minor7,
  ];

  @override
  List<ExerciseQuestion> generate(Exercise exercise, {int count = 10}) {
    final random = Random();

    // Resolve qualities.
    final qualityNames =
        (exercise.config['qualities'] as List<dynamic>?)?.cast<String>();
    final qualities = qualityNames != null
        ? ChordQuality.allQualities
            .where((q) =>
                qualityNames.any((n) => n.toLowerCase() == q.name.toLowerCase()))
            .toList()
        : List<ChordQuality>.from(_defaultQualities);

    if (qualities.isEmpty) {
      throw ArgumentError('No matching chord qualities found in config');
    }

    // Resolve roots.
    final rootValues =
        (exercise.config['roots'] as List<dynamic>?)?.cast<int>();
    final roots = rootValues != null
        ? rootValues.map((v) => PitchClass(v)).toList()
        : List.generate(12, (i) => PitchClass(i));

    final questions = <ExerciseQuestion>[];

    for (var i = 0; i < count; i++) {
      final quality = qualities[random.nextInt(qualities.length)];
      final root = roots[random.nextInt(roots.length)];
      final guides = guideTones(root, quality);
      final rootName = NoteName.toFlat(root);

      final correctAnswer =
          guides.map((pc) => NoteName.toFlat(pc)).join(' & ');

      // Build 4 MCQ options.
      final options = <String>{correctAnswer};
      while (options.length < 4) {
        // Pick two random pitch classes as a decoy pair.
        final a = PitchClass(random.nextInt(12));
        final b = PitchClass(random.nextInt(12));
        if (a == b) continue;
        final decoy =
            '${NoteName.toFlat(a)} & ${NoteName.toFlat(b)}';
        if (decoy != correctAnswer) {
          options.add(decoy);
        }
      }

      final shuffled = options.toList()..shuffle(random);

      questions.add(ExerciseQuestion(
        promptText:
            'What are the guide tones (3rd & 7th) of $rootName${quality.symbol}?',
        expectedAnswer: correctAnswer,
        multipleChoiceOptions: shuffled,
        metadata: {
          'root': root.value,
          'quality': quality.name,
          'guideTones': guides.map((pc) => pc.value).toList(),
        },
      ));
    }

    return questions;
  }
}
