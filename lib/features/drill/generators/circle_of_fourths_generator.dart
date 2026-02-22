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
  /// The subMode can be set explicitly in exercise config, or inferred
  /// from the generatorId ('circle_of_fourths_chord' → 'playChord').
  String _subMode(Exercise exercise) {
    final explicit = exercise.config['subMode'] as String?;
    if (explicit != null) return explicit;
    if (exercise.generatorId == 'circle_of_fourths_chord') return 'playChord';
    return 'nextKey';
  }

  @override
  List<String> allItemIds(Exercise exercise) {
    final fourths = CircleOfFifths.fourthsOrder;
    if (_subMode(exercise) == 'playChord') {
      final qualityName =
          exercise.config['chordQuality'] as String? ?? 'Major';
      final quality = ChordQuality.allQualities.firstWhere(
        (q) => q.name.toLowerCase() == qualityName.toLowerCase(),
        orElse: () => ChordQuality.major,
      );
      return fourths
          .map((pc) => '${NoteName.toFlat(pc)}${quality.symbol}')
          .toList();
    }
    return fourths.map((pc) => NoteName.toFlat(pc)).toList();
  }

  @override
  Map<String, List<String>> itemGroups(Exercise exercise) {
    return {'All': allItemIds(exercise)};
  }

  @override
  List<ExerciseQuestion> generateForItems(
      Exercise exercise, List<String> itemIds) {
    final fourths = CircleOfFifths.fourthsOrder;
    final random = Random();

    if (_subMode(exercise) == 'playChord') {
      return _generatePlayChordForItems(exercise, fourths, itemIds, random);
    }
    return _generateNextKeyForItems(fourths, itemIds, random);
  }

  @override
  List<ExerciseQuestion> generate(Exercise exercise, {int count = 10}) {
    final random = Random();
    final fourths = CircleOfFifths.fourthsOrder;

    if (_subMode(exercise) == 'playChord') {
      return _generatePlayChordQuestions(exercise, fourths, random, count);
    }
    return _generateNextKeyQuestions(fourths, random, count);
  }

  // --- nextKey mode ---

  List<ExerciseQuestion> _generateNextKeyForItems(
    List<PitchClass> fourths,
    List<String> itemIds,
    Random random,
  ) {
    final nameToIndex = <String, int>{};
    for (var i = 0; i < fourths.length; i++) {
      nameToIndex[NoteName.toFlat(fourths[i])] = i;
    }

    final questions = <ExerciseQuestion>[];
    for (final id in itemIds) {
      final index = nameToIndex[id];
      if (index == null) continue;
      questions.add(_buildNextKeyQuestion(fourths, index, random));
    }
    return questions;
  }

  List<ExerciseQuestion> _generateNextKeyQuestions(
    List<PitchClass> fourths,
    Random random,
    int count,
  ) {
    final questions = <ExerciseQuestion>[];
    for (var i = 0; i < count; i++) {
      final index = random.nextInt(12);
      questions.add(_buildNextKeyQuestion(fourths, index, random));
    }
    return questions;
  }

  ExerciseQuestion _buildNextKeyQuestion(
    List<PitchClass> fourths,
    int index,
    Random random,
  ) {
    final currentKey = fourths[index];
    final nextKey = fourths[(index + 1) % 12];
    final correctName = NoteName.toFlat(nextKey);

    final options = <String>{correctName};
    while (options.length < 4) {
      final randPc = PitchClass(random.nextInt(12));
      final name = NoteName.toFlat(randPc);
      if (name != correctName) {
        options.add(name);
      }
    }
    final shuffled = options.toList()..shuffle(random);

    return ExerciseQuestion(
      promptText:
          'What key comes after ${NoteName.toFlat(currentKey)} in the circle of fourths?',
      expectedAnswer: correctName,
      multipleChoiceOptions: shuffled,
      metadata: {
        'topic': 'circle-of-fourths',
        'skill': 'identify',
        'root': currentKey.value,
        'itemId': NoteName.toFlat(currentKey),
        'currentKey': currentKey.value,
        'nextKey': nextKey.value,
      },
    );
  }

  // --- playChord mode ---

  List<ExerciseQuestion> _generatePlayChordForItems(
    Exercise exercise,
    List<PitchClass> fourths,
    List<String> itemIds,
    Random random,
  ) {
    final qualityName =
        exercise.config['chordQuality'] as String? ?? 'Major';
    final quality = ChordQuality.allQualities.firstWhere(
      (q) => q.name.toLowerCase() == qualityName.toLowerCase(),
      orElse: () => ChordQuality.major,
    );

    final nameToRoot = <String, PitchClass>{};
    for (final pc in fourths) {
      nameToRoot['${NoteName.toFlat(pc)}${quality.symbol}'] = pc;
    }

    final questions = <ExerciseQuestion>[];
    for (final id in itemIds) {
      final root = nameToRoot[id];
      if (root == null) continue;
      questions.add(_buildPlayChordQuestion(root, quality));
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
      questions.add(_buildPlayChordQuestion(root, quality));
    }
    return questions;
  }

  ExerciseQuestion _buildPlayChordQuestion(
      PitchClass root, ChordQuality quality) {
    final chordTones = quality.build(root);
    final expectedPitchClasses = chordTones.toSet();
    final rootName = NoteName.toFlat(root);

    return ExerciseQuestion(
      promptText: 'Play $rootName${quality.symbol}',
      notationData: NotationData(
        pitches: chordTones,
        label: '$rootName${quality.symbol}',
      ),
      expectedAnswer: expectedPitchClasses,
      answerText: chordTones.map((pc) => NoteName.toFlat(pc)).join(', '),
      metadata: {
        'topic': 'circle-of-fourths',
        'skill': 'build',
        'root': root.value,
        'itemId': '$rootName${quality.symbol}',
        'quality': quality.name,
      },
    );
  }
}
