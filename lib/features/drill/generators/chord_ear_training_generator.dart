import 'dart:math';

import '../../../core/audio/audio_service.dart';
import '../../../core/audio/pitched_note.dart';
import '../../../core/music/chord_quality.dart';
import '../../../core/music/note_name.dart';
import '../../../core/music/pitch_class.dart';
import '../../../domain/models/exercise.dart';
import '../runner/exercise_question.dart';
import '../runner/question_generator.dart';

/// Generates ear training questions for chords: plays a chord, user identifies quality.
///
/// Configuration via `exercise.config`:
/// - `qualities` (`List<String>?`): Chord quality names to include.
/// - `roots` (`List<int>?`): Pitch-class values for chord roots.
/// - `baseOctave` (`int?`): Octave for the root note (default 3).
class ChordEarTrainingGenerator extends QuestionGenerator {
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
    final baseOctave = exercise.config['baseOctave'] as int? ?? 3;
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
      questions.add(
          _buildQuestion(quality, root, baseOctave, qualities, fixedNamer, random));
    }
    return questions;
  }

  @override
  List<ExerciseQuestion> generate(Exercise exercise, {int count = 10}) {
    final random = Random();
    final qualities = _resolveQualities(exercise);
    final roots = _resolveRoots(exercise);
    final baseOctave = exercise.config['baseOctave'] as int? ?? 3;
    final fixedNamer = NoteName.namerForStyle(
        exercise.config['noteDisplayStyle'] as String?);
    final questions = <ExerciseQuestion>[];

    for (var i = 0; i < count; i++) {
      final quality = qualities[random.nextInt(qualities.length)];
      final root = roots[random.nextInt(roots.length)];
      questions.add(
          _buildQuestion(quality, root, baseOctave, qualities, fixedNamer, random));
    }

    return questions;
  }

  ExerciseQuestion _buildQuestion(
    ChordQuality quality,
    PitchClass root,
    int baseOctave,
    List<ChordQuality> allQualities,
    String Function(PitchClass)? fixedNamer,
    Random random,
  ) {
    final chordTones = quality.build(root);
    final noteName = fixedNamer ?? NoteName.namerForRoot(root);
    final rootName = noteName(root);
    final correctAnswer = quality.name;

    // Build audio notes
    final rootNote = PitchedNote(root, baseOctave);
    final audioNotes = chordTones
        .map((pc) {
          final semitones = root.intervalTo(pc);
          return rootNote.transpose(semitones);
        })
        .toList();

    // Build MCQ options
    final options = <String>{correctAnswer};
    var attempts = 0;
    while (options.length < 4 && attempts < 100) {
      attempts++;
      final randQuality = allQualities[random.nextInt(allQualities.length)];
      if (randQuality.name != correctAnswer) {
        options.add(randQuality.name);
      }
      if (options.length < 4 && allQualities.length < 4) {
        final fallback = ChordQuality
            .allQualities[random.nextInt(ChordQuality.allQualities.length)];
        if (fallback.name != correctAnswer) {
          options.add(fallback.name);
        }
      }
    }
    final shuffled = options.toList()..shuffle(random);

    return ExerciseQuestion(
      promptText: 'Listen and identify the chord quality of $rootName',
      expectedAnswer: correctAnswer,
      multipleChoiceOptions: shuffled,
      audioData: AudioQuestionData(
        notes: audioNotes,
        playbackMode: PlaybackMode.chord,
      ),
      metadata: {
        'topic': 'chords',
        'skill': 'ear_training',
        'root': root.value,
        'itemId': '${quality.name}:${NoteName.toFlat(root)}',
        'quality': quality.name,
        'chordTones': chordTones.map((pc) => pc.value).toList(),
      },
    );
  }
}
