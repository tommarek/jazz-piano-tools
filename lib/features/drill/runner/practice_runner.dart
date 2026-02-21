import '../../../core/answer_checker/answer_checker.dart';
import 'exercise_runner.dart';

/// A practice-mode runner that optionally shows hints after mistakes.
class PracticeRunner extends ExerciseRunner {
  final bool showHintsAfterMistake;

  /// Tracks whether the most recent answer was incorrect, so the UI
  /// can display a hint before advancing.
  AnswerResult? _lastResult;

  PracticeRunner({
    required super.exercise,
    required super.generator,
    required super.checkAnswer,
    this.showHintsAfterMistake = true,
  });

  /// The result of the most recently submitted answer, useful for
  /// deciding whether to show a hint.
  AnswerResult? get lastResult => _lastResult;

  /// Whether a hint should currently be displayed (i.e. the last
  /// answer was wrong and [showHintsAfterMistake] is enabled).
  bool get shouldShowHint =>
      showHintsAfterMistake &&
      _lastResult != null &&
      !_lastResult!.isCorrect;

  @override
  AnswerResult submitAnswer(dynamic answer) {
    _lastResult = super.submitAnswer(answer);
    return _lastResult!;
  }
}
