import 'package:freezed_annotation/freezed_annotation.dart';

part 'exercise_attempt.freezed.dart';
part 'exercise_attempt.g.dart';

@freezed
abstract class ExerciseAttempt with _$ExerciseAttempt {
  const factory ExerciseAttempt({
    required String id,
    required String exerciseId,
    required double score,
    required int durationSeconds,
    String? key,
    required DateTime timestamp,
    @Default({}) Map<String, dynamic> details,
  }) = _ExerciseAttempt;

  factory ExerciseAttempt.fromJson(Map<String, dynamic> json) =>
      _$ExerciseAttemptFromJson(json);
}
