import 'package:uuid/uuid.dart';

import '../../../core/answer_checker/answer_checker.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/models/exercise_attempt.dart';
import 'exercise_question.dart';
import 'question_generator.dart';

typedef AnswerCheckFn = AnswerResult Function(
    dynamic expected, dynamic actual);

/// Runs an exercise session, tracking questions, score, and timing.
class ExerciseRunner {
  final Exercise exercise;
  final QuestionGenerator generator;
  final AnswerCheckFn checkAnswer;

  List<ExerciseQuestion> _questions = [];
  int _currentIndex = 0;
  int _correctCount = 0;
  int _totalAnswered = 0;
  final Stopwatch _stopwatch = Stopwatch();
  final List<AnswerResult> _results = [];

  ExerciseRunner({
    required this.exercise,
    required this.generator,
    required this.checkAnswer,
  });

  // ── Lifecycle ──────────────────────────────────────────────────

  /// Generates questions and starts the timer.
  void start({int questionCount = 10}) {
    _questions = generator.generate(exercise, count: questionCount);
    _currentIndex = 0;
    _correctCount = 0;
    _totalAnswered = 0;
    _results.clear();
    _stopwatch
      ..reset()
      ..start();
  }

  // ── Getters ────────────────────────────────────────────────────

  ExerciseQuestion get currentQuestion => _questions[_currentIndex];

  int get currentIndex => _currentIndex;

  int get totalQuestions => _questions.length;

  bool get isComplete => _currentIndex >= _questions.length;

  double get currentScore =>
      _totalAnswered == 0 ? 0.0 : _correctCount / _totalAnswered;

  int get correctCount => _correctCount;

  int get totalAnswered => _totalAnswered;

  List<AnswerResult> get results => List.unmodifiable(_results);

  Duration get elapsed => _stopwatch.elapsed;

  // ── Actions ────────────────────────────────────────────────────

  /// Checks the given [answer] against the current question,
  /// records the result, and advances to the next question.
  AnswerResult submitAnswer(dynamic answer) {
    if (isComplete) {
      throw StateError('Exercise is already complete');
    }

    final question = _questions[_currentIndex];
    final result = checkAnswer(question.expectedAnswer, answer);

    _results.add(result);
    _totalAnswered++;
    if (result.isCorrect) {
      _correctCount++;
    }
    _currentIndex++;

    return result;
  }

  /// Stops the timer and returns an [ExerciseAttempt] summarising
  /// this session.
  ExerciseAttempt finalize() {
    _stopwatch.stop();

    return ExerciseAttempt(
      id: const Uuid().v4(),
      exerciseId: exercise.id,
      score: currentScore,
      durationSeconds: _stopwatch.elapsed.inSeconds,
      timestamp: DateTime.now(),
      details: {
        'totalQuestions': totalQuestions,
        'correctCount': _correctCount,
        'totalAnswered': _totalAnswered,
      },
    );
  }
}
