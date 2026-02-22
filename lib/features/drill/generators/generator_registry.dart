import '../runner/question_generator.dart';
import 'interval_build_generator.dart';
import 'interval_ear_training_generator.dart';
import 'interval_find_generator.dart';
import 'chord_build_generator.dart';
import 'chord_ear_training_generator.dart';
import 'ii_v_i_shell_generator.dart';
import 'circle_of_fourths_generator.dart';
import 'guide_tone_generator.dart';

/// Returns the [QuestionGenerator] matching the given [generatorId].
///
/// Generator IDs correspond to the `generatorId` field in exercise JSON.
QuestionGenerator resolveGenerator(String generatorId) {
  return switch (generatorId) {
    'interval_build' => IntervalBuildGenerator(),
    'interval_ear_training' => IntervalEarTrainingGenerator(),
    'interval_find' => IntervalFindGenerator(),
    'chord_build' => ChordBuildGenerator(),
    'chord_ear_training' => ChordEarTrainingGenerator(),
    'ii_v_i_shells' => IiViShellGenerator(),
    'circle_of_fourths_next' => CircleOfFourthsGenerator(),
    'circle_of_fourths_chord' => CircleOfFourthsGenerator(),
    'guide_tone_identify' => GuideToneGenerator(),
    _ => throw ArgumentError('Unknown generator: $generatorId'),
  };
}

/// Returns the SRS topic string for a given [generatorId].
String? topicForGenerator(String generatorId) {
  return switch (generatorId) {
    'interval_build' ||
    'interval_ear_training' ||
    'interval_find' => 'intervals',
    'chord_build' ||
    'chord_ear_training' => 'chords',
    'ii_v_i_shells' ||
    'guide_tone_identify' => 'voicings',
    'circle_of_fourths_next' ||
    'circle_of_fourths_chord' => 'circle-of-fourths',
    _ => null,
  };
}
