import 'dart:math';

import '../../../core/audio/audio_service.dart';
import '../../../core/audio/pitched_note.dart';
import '../../../core/music/interval.dart';
import '../../../core/music/note_name.dart';
import '../../../core/music/pitch_class.dart';
import '../../../domain/models/exercise.dart';
import '../runner/exercise_question.dart';
import '../runner/question_generator.dart';

/// Generates ear training questions: plays an interval, user identifies it via MCQ.
///
/// Configuration via `exercise.config`:
/// - `intervals` (`List<int>?`): Semitone values to drill.
/// - `roots` (`List<int>?`): Pitch-class values for the root note.
/// - `baseOctave` (`int?`): Octave for the root note (default 4).
class IntervalEarTrainingGenerator extends QuestionGenerator {
  List<Interval> _resolveIntervals(Exercise exercise) {
    final raw = exercise.config['intervals'];
    final intervalValues = (raw is List ? raw : null)?.cast<int>();
    return intervalValues != null
        ? intervalValues.map((v) {
            if (v < 12) return Interval.values[v % 12];
            return Interval.all.firstWhere((i) => i.semitones == v,
                orElse: () => Interval.fromSemitones(v));
          }).toList()
        : Interval.values.where((i) => i != Interval.unison).toList();
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
    final intervals = _resolveIntervals(exercise);
    final roots = _resolveRoots(exercise);
    final ids = <String>[];
    for (final interval in intervals) {
      for (final root in roots) {
        ids.add('${interval.fullName}:${NoteName.toFlat(root)}');
      }
    }
    return ids;
  }

  @override
  Map<String, List<String>> itemGroups(Exercise exercise) {
    final intervals = _resolveIntervals(exercise);
    final roots = _resolveRoots(exercise);
    final groups = <String, List<String>>{};
    for (final interval in intervals) {
      groups[interval.fullName] = roots
          .map((r) => '${interval.fullName}:${NoteName.toFlat(r)}')
          .toList();
    }
    return groups;
  }

  @override
  List<ExerciseQuestion> generateForItems(
      Exercise exercise, List<String> itemIds) {
    final intervals = _resolveIntervals(exercise);
    final roots = _resolveRoots(exercise);
    final random = Random();
    final baseOctave = exercise.config['baseOctave'] as int? ?? 4;
    final fixedNamer = NoteName.namerForStyle(
        exercise.config['noteDisplayStyle'] as String?);
    final questions = <ExerciseQuestion>[];

    final intervalMap = {for (final i in intervals) i.fullName: i};
    final rootMap = {for (final r in roots) NoteName.toFlat(r): r};

    for (final id in itemIds) {
      final parts = id.split(':');
      final interval = intervalMap[parts[0]];
      if (interval == null) continue; // skip items not in current config
      final root = parts.length > 1 ? rootMap[parts[1]] : null;
      if (root == null) continue; // skip items with unknown root
      questions.add(
          _buildQuestion(interval, root, baseOctave, intervals, fixedNamer, random));
    }
    return questions;
  }

  @override
  List<ExerciseQuestion> generate(Exercise exercise, {int count = 10}) {
    final random = Random();
    final intervals = _resolveIntervals(exercise);
    final roots = _resolveRoots(exercise);
    final baseOctave = exercise.config['baseOctave'] as int? ?? 4;
    final fixedNamer = NoteName.namerForStyle(
        exercise.config['noteDisplayStyle'] as String?);
    final questions = <ExerciseQuestion>[];

    for (var i = 0; i < count; i++) {
      final interval = intervals[random.nextInt(intervals.length)];
      final root = roots[random.nextInt(roots.length)];
      questions.add(
          _buildQuestion(interval, root, baseOctave, intervals, fixedNamer, random));
    }

    return questions;
  }

  ExerciseQuestion _buildQuestion(
    Interval interval,
    PitchClass root,
    int baseOctave,
    List<Interval> allIntervals,
    String Function(PitchClass)? fixedNamer,
    Random random,
  ) {
    final rootNote = PitchedNote(root, baseOctave);
    final targetNote = rootNote.transpose(interval.semitones);
    final correctAnswer = interval.fullName;

    // Build MCQ options
    final options = <String>{correctAnswer};
    var attempts = 0;
    while (options.length < 4 && attempts < 100) {
      attempts++;
      final randInterval = allIntervals[random.nextInt(allIntervals.length)];
      if (randInterval.fullName != correctAnswer) {
        options.add(randInterval.fullName);
      }
      if (options.length < 4 && allIntervals.length < 4) {
        final fallback =
            Interval.values[random.nextInt(Interval.values.length)];
        if (fallback.fullName != correctAnswer) {
          options.add(fallback.fullName);
        }
      }
    }
    final shuffled = options.toList()..shuffle(random);

    return ExerciseQuestion(
      promptText: 'Listen and identify the interval',
      expectedAnswer: correctAnswer,
      multipleChoiceOptions: shuffled,
      audioData: AudioQuestionData(
        notes: [rootNote, targetNote],
        playbackMode: PlaybackMode.melodicAscending,
      ),
      metadata: {
        'topic': 'intervals',
        'skill': 'ear_training',
        'root': root.value,
        'itemId': '${interval.fullName}:${NoteName.toFlat(root)}',
        'rootName': (fixedNamer ?? NoteName.namerForRoot(root))(root),
        'interval': interval.semitones,
        'intervalName': interval.fullName,
      },
    );
  }
}
