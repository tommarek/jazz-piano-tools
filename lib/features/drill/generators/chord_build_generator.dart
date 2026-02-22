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
  List<ChordQuality> _resolveQualities(Exercise exercise) {
    final rawQualities = exercise.config['qualities'];
    final qualityNames =
        (rawQualities is List ? rawQualities : null)?.cast<String>();
    final qualities = qualityNames != null
        ? ChordQuality.allQualities
            .where((q) =>
                qualityNames.any((n) => n.toLowerCase() == q.name.toLowerCase()))
            .toList()
        : List<ChordQuality>.from(ChordQuality.allQualities);
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
    for (final quality in qualities) {
      for (final root in roots) {
        ids.add('${quality.name}:${NoteName.toFlat(root)}');
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
          .map((r) => '${quality.name}:${NoteName.toFlat(r)}')
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
    final fixedNamer = NoteName.namerForStyle(
        exercise.config['noteDisplayStyle'] as String?);
    final questions = <ExerciseQuestion>[];

    final qualityMap = {for (final q in qualities) q.name: q};
    final rootMap = {for (final r in roots) NoteName.toFlat(r): r};

    for (final id in itemIds) {
      final parts = id.split(':');
      final quality = qualityMap[parts[0]];
      if (quality == null) continue; // skip items not in current config
      final root = parts.length > 1 ? rootMap[parts[1]] : null;
      if (root == null) continue; // skip items with unknown root
      questions.add(_buildQuestion(quality, root, fixedNamer));
    }
    return questions;
  }

  @override
  List<ExerciseQuestion> generate(Exercise exercise, {int count = 10}) {
    final random = Random();
    final qualities = _resolveQualities(exercise);
    final roots = _resolveRoots(exercise);
    final fixedNamer = NoteName.namerForStyle(
        exercise.config['noteDisplayStyle'] as String?);
    final questions = <ExerciseQuestion>[];

    for (var i = 0; i < count; i++) {
      final quality = qualities[random.nextInt(qualities.length)];
      final root = roots[random.nextInt(roots.length)];
      questions.add(_buildQuestion(quality, root, fixedNamer));
    }

    return questions;
  }

  ExerciseQuestion _buildQuestion(
    ChordQuality quality,
    PitchClass root,
    String Function(PitchClass)? fixedNamer,
  ) {
    final chordTones = quality.build(root);
    final expected = chordTones.toSet();
    final noteName = fixedNamer ?? NoteName.namerForRoot(root);
    final rootName = noteName(root);

    return ExerciseQuestion(
      promptText: 'Play $rootName${quality.symbol}',
      notationData: NotationData(
        pitches: chordTones,
        label: '$rootName${quality.symbol}',
      ),
      expectedAnswer: expected,
      answerText: chordTones.map((pc) => noteName(pc)).join(', '),
      metadata: {
        'topic': 'chords',
        'skill': 'build',
        'root': root.value,
        'itemId': '${quality.name}:${NoteName.toFlat(root)}',
        'quality': quality.name,
        'chordTones': chordTones.map((pc) => pc.value).toList(),
      },
    );
  }
}
