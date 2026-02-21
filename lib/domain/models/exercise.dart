import 'package:freezed_annotation/freezed_annotation.dart';

import '../enums/exercise_mode.dart';
import '../enums/input_type.dart';

part 'exercise.freezed.dart';
part 'exercise.g.dart';

@freezed
abstract class Exercise with _$Exercise {
  const factory Exercise({
    required String id,
    required String title,
    required ExerciseMode mode,
    required InputType inputType,
    required String generatorId,
    @Default({}) Map<String, dynamic> config,
    @Default({}) Map<String, dynamic> acceptanceRules,
    @Default({}) Map<String, dynamic> scoringRules,
    @Default([]) List<String> tags,
    @Default(1) int level,
    @Default(5) int estimatedMinutes,
  }) = _Exercise;

  factory Exercise.fromJson(Map<String, dynamic> json) =>
      _$ExerciseFromJson(json);
}
