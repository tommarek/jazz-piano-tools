import 'dart:math';

import '../../../core/music/chord_quality.dart';
import '../../../core/music/note_name.dart';
import '../../../core/music/pitch_class.dart';
import '../../../core/widgets/notation/notation_renderer.dart';
import '../../../domain/models/exercise.dart';
import '../runner/exercise_question.dart';
import '../runner/question_generator.dart';

/// Generates ii-V-I shell voicing questions.
///
/// A shell voicing consists of root, 3rd, and 7th (no 5th).
///
/// For a given key the progression is:
/// - ii: minor 7 (root a whole step above the key root) → shell = root, m3, m7
/// - V: dominant 7 (root a fifth above the key root) → shell = root, M3, m7
/// - I: major 7 (key root) → shell = root, M3, M7
///
/// Configuration via `exercise.config`:
/// - `keys` (`List<int>?`): Pitch-class values for key centres.
///   Defaults to all 12 keys.
/// - `chordIndex` (int?): If set, only ask about that chord in the
///   progression (0 = ii, 1 = V, 2 = I). Otherwise picks randomly.
class IiViShellGenerator extends QuestionGenerator {
  /// Shell voicing intervals (from root) for each chord quality.
  static const _shellIntervals = {
    'ii': [0, 3, 10], // root, m3, m7
    'V': [0, 4, 10], // root, M3, m7
    'I': [0, 4, 11], // root, M3, M7
  };

  static const _chordLabels = ['ii', 'V', 'I'];
  static const _qualities = [
    ChordQuality.minor7,
    ChordQuality.dominant7,
    ChordQuality.major7,
  ];

  /// Semitone offset from the key root for each chord.
  static const _rootOffsets = [2, 7, 0]; // ii = +2, V = +7, I = +0

  @override
  List<ExerciseQuestion> generate(Exercise exercise, {int count = 10}) {
    final random = Random();

    // Resolve which keys to drill.
    final keyValues =
        (exercise.config['keys'] as List<dynamic>?)?.cast<int>();
    final keys = keyValues != null
        ? keyValues.map((v) => PitchClass(v)).toList()
        : List.generate(12, (i) => PitchClass(i));

    final fixedChordIndex = exercise.config['chordIndex'] as int?;

    final questions = <ExerciseQuestion>[];

    for (var i = 0; i < count; i++) {
      final keyRoot = keys[random.nextInt(keys.length)];
      final chordIdx = fixedChordIndex ?? random.nextInt(3);
      final chordLabel = _chordLabels[chordIdx];
      final chordRoot = keyRoot.transpose(_rootOffsets[chordIdx]);

      final shellSemitones = _shellIntervals[chordLabel]!;
      final shellPitches =
          shellSemitones.map((s) => chordRoot.transpose(s)).toList();
      final expected = shellPitches.toSet();

      final keyName = NoteName.toFlat(keyRoot);
      final chordRootName = NoteName.toFlat(chordRoot);
      final quality = _qualities[chordIdx];

      questions.add(ExerciseQuestion(
        promptText:
            'Play the $chordLabel shell voicing in the key of $keyName '
            '($chordRootName${quality.symbol})',
        notationData: NotationData(
          pitches: shellPitches,
          label: '$chordRootName${quality.symbol} shell',
        ),
        expectedAnswer: expected,
        metadata: {
          'key': keyRoot.value,
          'chordLabel': chordLabel,
          'chordRoot': chordRoot.value,
          'shellPitches': shellPitches.map((pc) => pc.value).toList(),
        },
      ));
    }

    return questions;
  }
}
