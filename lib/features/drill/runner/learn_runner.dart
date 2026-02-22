import 'exercise_runner.dart';

/// A learn-mode runner that reveals answers immediately.
///
/// In learn mode there is no scoring — the user sees the prompt, then
/// taps to reveal the answer (or it auto-reveals). They can optionally
/// replay audio, then tap "Got it" or "Show again" to advance.
class LearnRunner extends ExerciseRunner {
  LearnRunner({
    required super.exercise,
    required super.generator,
    required super.checkAnswer,
  });

  /// In learn mode, every answer is considered "correct" because the
  /// goal is exposure, not assessment.
  bool get isLearnMode => true;
}
