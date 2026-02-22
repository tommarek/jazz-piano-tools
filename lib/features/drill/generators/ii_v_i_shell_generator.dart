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

  List<PitchClass> _resolveKeys(Exercise exercise) {
    final rawKeys = exercise.config['keys'];
    final keyValues = (rawKeys is List ? rawKeys : null)?.cast<int>();
    return keyValues != null
        ? keyValues.map((v) => PitchClass(v)).toList()
        : List.generate(12, (i) => PitchClass(i));
  }

  @override
  List<String> allItemIds(Exercise exercise) {
    final keys = _resolveKeys(exercise);
    final fixedChordIndex = exercise.config['chordIndex'] as int?;
    final ids = <String>[];
    for (final keyRoot in keys) {
      final keyName = NoteName.toFlat(keyRoot);
      if (fixedChordIndex != null) {
        ids.add('${_chordLabels[fixedChordIndex]}-$keyName');
      } else {
        for (final label in _chordLabels) {
          ids.add('$label-$keyName');
        }
      }
    }
    return ids;
  }

  @override
  Map<String, List<String>> itemGroups(Exercise exercise) {
    final keys = _resolveKeys(exercise);
    final fixedChordIndex = exercise.config['chordIndex'] as int?;
    final groups = <String, List<String>>{};
    if (fixedChordIndex != null) {
      final label = _chordLabels[fixedChordIndex];
      groups[label] = keys
          .map((k) => '$label-${NoteName.toFlat(k)}')
          .toList();
    } else {
      for (final label in _chordLabels) {
        groups[label] = keys
            .map((k) => '$label-${NoteName.toFlat(k)}')
            .toList();
      }
    }
    return groups;
  }

  @override
  List<ExerciseQuestion> generateForItems(
      Exercise exercise, List<String> itemIds) {
    final questions = <ExerciseQuestion>[];
    final keys = _resolveKeys(exercise);
    final keyMap = {for (final k in keys) NoteName.toFlat(k): k};

    for (final id in itemIds) {
      final dashIdx = id.indexOf('-');
      if (dashIdx < 0) continue;
      final chordLabel = id.substring(0, dashIdx);
      final keyName = id.substring(dashIdx + 1);
      final chordIdx = _chordLabels.indexOf(chordLabel);
      if (chordIdx < 0) continue;
      final keyRoot = keyMap[keyName];
      if (keyRoot == null) continue;
      questions.add(_buildQuestion(keyRoot, chordIdx));
    }
    return questions;
  }

  @override
  List<ExerciseQuestion> generate(Exercise exercise, {int count = 10}) {
    final random = Random();
    final keys = _resolveKeys(exercise);
    final fixedChordIndex = exercise.config['chordIndex'] as int?;
    final questions = <ExerciseQuestion>[];

    for (var i = 0; i < count; i++) {
      final keyRoot = keys[random.nextInt(keys.length)];
      final chordIdx = fixedChordIndex ?? random.nextInt(3);
      questions.add(_buildQuestion(keyRoot, chordIdx));
    }

    return questions;
  }

  ExerciseQuestion _buildQuestion(PitchClass keyRoot, int chordIdx) {
    final chordLabel = _chordLabels[chordIdx];
    final chordRoot = keyRoot.transpose(_rootOffsets[chordIdx]);

    final shellSemitones = _shellIntervals[chordLabel]!;
    final shellPitches =
        shellSemitones.map((s) => chordRoot.transpose(s)).toList();
    final expected = shellPitches.toSet();

    final keyName = NoteName.toFlat(keyRoot);
    final chordRootName = NoteName.toFlat(chordRoot);
    final quality = _qualities[chordIdx];

    return ExerciseQuestion(
      promptText:
          'Play the $chordLabel shell voicing in the key of $keyName '
          '($chordRootName${quality.symbol})',
      notationData: NotationData(
        pitches: shellPitches,
        label: '$chordRootName${quality.symbol} shell',
      ),
      expectedAnswer: expected,
      answerText: shellPitches.map((pc) => NoteName.toFlat(pc)).join(', '),
      metadata: {
        'topic': 'voicings',
        'skill': 'build',
        'root': chordRoot.value,
        'itemId': '$chordLabel-$keyName',
        'key': keyRoot.value,
        'chordLabel': chordLabel,
        'chordRoot': chordRoot.value,
        'shellPitches': shellPitches.map((pc) => pc.value).toList(),
      },
    );
  }
}
