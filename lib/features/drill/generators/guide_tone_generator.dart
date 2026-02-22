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

  List<ChordQuality> _resolveQualities(Exercise exercise) {
    final rawQualities = exercise.config['qualities'];
    final qualityNames =
        (rawQualities is List ? rawQualities : null)?.cast<String>();
    final qualities = qualityNames != null
        ? ChordQuality.allQualities
            .where((q) =>
                qualityNames.any((n) => n.toLowerCase() == q.name.toLowerCase()))
            .toList()
        : List<ChordQuality>.from(_defaultQualities);
    if (qualities.isEmpty) {
      throw ArgumentError('No matching chord qualities found in config');
    }
    return qualities;
  }

  List<PitchClass> _resolveRoots(Exercise exercise) {
    final rawRoots = exercise.config['roots'];
    final rootValues = (rawRoots is List ? rawRoots : null)?.cast<int>();
    return rootValues != null
        ? rootValues.map((v) => PitchClass(v)).toList()
        : List.generate(12, (i) => PitchClass(i));
  }

  @override
  List<String> allItemIds(Exercise exercise) {
    final qualities = _resolveQualities(exercise);
    final roots = _resolveRoots(exercise);
    final ids = <String>[];
    for (final root in roots) {
      for (final quality in qualities) {
        ids.add('${NoteName.toFlat(root)}${quality.symbol}');
      }
    }
    return ids;
  }

  @override
  Map<String, List<String>> itemGroups(Exercise exercise) {
    final qualities = _resolveQualities(exercise);
    final roots = _resolveRoots(exercise);
    final groups = <String, List<String>>{};
    for (final quality in qualities) {
      groups[quality.name] = roots
          .map((r) => '${NoteName.toFlat(r)}${quality.symbol}')
          .toList();
    }
    return groups;
  }

  @override
  List<ExerciseQuestion> generateForItems(
      Exercise exercise, List<String> itemIds) {
    final qualities = _resolveQualities(exercise);
    final roots = _resolveRoots(exercise);
    final random = Random();

    // Build lookup: itemId → (root, quality)
    final lookup = <String, (PitchClass, ChordQuality)>{};
    for (final root in roots) {
      for (final quality in qualities) {
        lookup['${NoteName.toFlat(root)}${quality.symbol}'] = (root, quality);
      }
    }

    final questions = <ExerciseQuestion>[];
    for (final id in itemIds) {
      final pair = lookup[id];
      if (pair == null) continue;
      questions.add(_buildQuestion(pair.$1, pair.$2, qualities, random));
    }
    return questions;
  }

  @override
  List<ExerciseQuestion> generate(Exercise exercise, {int count = 10}) {
    final random = Random();
    final qualities = _resolveQualities(exercise);
    final roots = _resolveRoots(exercise);
    final questions = <ExerciseQuestion>[];

    for (var i = 0; i < count; i++) {
      final quality = qualities[random.nextInt(qualities.length)];
      final root = roots[random.nextInt(roots.length)];
      questions.add(_buildQuestion(root, quality, qualities, random));
    }

    return questions;
  }

  ExerciseQuestion _buildQuestion(
    PitchClass root,
    ChordQuality quality,
    List<ChordQuality> allQualities,
    Random random,
  ) {
    final guides = guideTones(root, quality);
    final rootName = NoteName.toFlat(root);
    final correctAnswer =
        guides.map((pc) => NoteName.toFlat(pc)).join(' & ');

    // Build 4 MCQ options matching the format of the correct answer.
    final isSingleNote = guides.length == 1;
    final options = <String>{correctAnswer};
    var attempts = 0;
    while (options.length < 4 && attempts < 100) {
      attempts++;
      if (isSingleNote) {
        // For triads (single guide tone), generate single-note decoys.
        final decoyPc = PitchClass(random.nextInt(12));
        final decoy = NoteName.toFlat(decoyPc);
        if (decoy != correctAnswer) {
          options.add(decoy);
        }
      } else {
        final a = PitchClass(random.nextInt(12));
        final b = PitchClass(random.nextInt(12));
        if (a == b) continue;
        final decoy = '${NoteName.toFlat(a)} & ${NoteName.toFlat(b)}';
        if (decoy != correctAnswer) {
          options.add(decoy);
        }
      }
    }
    final shuffled = options.toList()..shuffle(random);

    return ExerciseQuestion(
      promptText:
          'What are the guide tones (3rd & 7th) of $rootName${quality.symbol}?',
      expectedAnswer: correctAnswer,
      multipleChoiceOptions: shuffled,
      metadata: {
        'topic': 'voicings',
        'skill': 'identify',
        'root': root.value,
        'itemId': '$rootName${quality.symbol}',
        'quality': quality.name,
        'guideTones': guides.map((pc) => pc.value).toList(),
      },
    );
  }
}
