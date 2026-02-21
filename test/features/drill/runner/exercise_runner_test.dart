import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/features/drill/runner/exercise_runner.dart';
import 'package:jazz_piano_tools/features/drill/runner/exercise_question.dart';
import 'package:jazz_piano_tools/features/drill/runner/question_generator.dart';
import 'package:jazz_piano_tools/core/answer_checker/answer_checker.dart';
import 'package:jazz_piano_tools/domain/enums/exercise_mode.dart';
import 'package:jazz_piano_tools/domain/enums/input_type.dart';
import 'package:jazz_piano_tools/domain/models/exercise.dart';

// ---------------------------------------------------------------------------
// Mock QuestionGenerator that returns a fixed list of questions.
// ---------------------------------------------------------------------------
class MockQuestionGenerator implements QuestionGenerator {
  final List<ExerciseQuestion> fixedQuestions;

  MockQuestionGenerator(this.fixedQuestions);

  @override
  List<ExerciseQuestion> generate(Exercise exercise, {int count = 10}) {
    return fixedQuestions.take(count).toList();
  }
}

// ---------------------------------------------------------------------------
// Simple answer check function: compares expected and actual as strings.
// ---------------------------------------------------------------------------
AnswerResult simpleAnswerCheck(dynamic expected, dynamic actual) {
  final isCorrect = expected.toString() == actual.toString();
  return AnswerResult(
    isCorrect: isCorrect,
    score: isCorrect ? 1.0 : 0.0,
    feedback: isCorrect ? null : 'Expected "$expected" but got "$actual"',
  );
}

void main() {
  // Shared fixtures ---------------------------------------------------------
  late Exercise exercise;
  late List<ExerciseQuestion> questions;
  late MockQuestionGenerator generator;
  late ExerciseRunner runner;

  setUp(() {
    exercise = const Exercise(
      id: 'ex-1',
      title: 'Name That Note',
      mode: ExerciseMode.drill,
      inputType: InputType.text,
      generatorId: 'mock',
    );

    questions = const [
      ExerciseQuestion(promptText: 'What note is this?', expectedAnswer: 'C'),
      ExerciseQuestion(promptText: 'What note is this?', expectedAnswer: 'E'),
      ExerciseQuestion(promptText: 'What note is this?', expectedAnswer: 'G'),
    ];

    generator = MockQuestionGenerator(questions);

    runner = ExerciseRunner(
      exercise: exercise,
      generator: generator,
      checkAnswer: simpleAnswerCheck,
    );
  });

  group('ExerciseRunner', () {
    // 1. start() generates questions from the generator ---------------------
    test('start() generates questions from generator', () {
      runner.start(questionCount: 3);

      expect(runner.totalQuestions, equals(3));
      expect(runner.currentIndex, equals(0));
      expect(runner.isComplete, isFalse);
      expect(runner.currentQuestion.expectedAnswer, equals('C'));
    });

    // 2. submitAnswer correct -> score increases, isCorrect=true ------------
    test('submitAnswer correct increases score and returns isCorrect true',
        () {
      runner.start(questionCount: 3);

      final result = runner.submitAnswer('C');

      expect(result.isCorrect, isTrue);
      expect(result.score, equals(1.0));
      expect(runner.correctCount, equals(1));
      expect(runner.totalAnswered, equals(1));
      expect(runner.currentScore, equals(1.0));
      expect(runner.currentIndex, equals(1));
    });

    // 3. submitAnswer wrong -> score stays, feedback returned ---------------
    test('submitAnswer wrong keeps score at zero and returns feedback', () {
      runner.start(questionCount: 3);

      final result = runner.submitAnswer('D');

      expect(result.isCorrect, isFalse);
      expect(result.feedback, isNotNull);
      expect(result.feedback, contains('C'));
      expect(runner.correctCount, equals(0));
      expect(runner.totalAnswered, equals(1));
      expect(runner.currentScore, equals(0.0));
    });

    // 4. Complete all questions -> isComplete=true --------------------------
    test('isComplete is true after answering all questions', () {
      runner.start(questionCount: 3);

      runner.submitAnswer('C'); // correct
      runner.submitAnswer('E'); // correct
      runner.submitAnswer('G'); // correct

      expect(runner.isComplete, isTrue);
      expect(runner.totalAnswered, equals(3));
      expect(runner.correctCount, equals(3));
      expect(runner.currentScore, equals(1.0));
      expect(runner.results, hasLength(3));
    });

    // 5. finalize() -> ExerciseAttempt with correct score and duration ------
    test('finalize() returns ExerciseAttempt with correct score and duration',
        () {
      runner.start(questionCount: 3);

      runner.submitAnswer('C'); // correct
      runner.submitAnswer('X'); // wrong
      runner.submitAnswer('G'); // correct

      final attempt = runner.finalize();

      expect(attempt.exerciseId, equals('ex-1'));
      expect(attempt.score, closeTo(2 / 3, 0.001));
      expect(attempt.durationSeconds, greaterThanOrEqualTo(0));
      expect(attempt.details['totalQuestions'], equals(3));
      expect(attempt.details['correctCount'], equals(2));
      expect(attempt.details['totalAnswered'], equals(3));
    });

    // 6. Cannot submit after isComplete -------------------------------------
    test('submitAnswer throws StateError after exercise is complete', () {
      runner.start(questionCount: 3);

      runner.submitAnswer('C');
      runner.submitAnswer('E');
      runner.submitAnswer('G');

      expect(runner.isComplete, isTrue);
      expect(
        () => runner.submitAnswer('A'),
        throwsA(isA<StateError>()),
      );
    });

    // Additional useful tests -----------------------------------------------

    test('start() resets state when called again', () {
      runner.start(questionCount: 3);

      runner.submitAnswer('C');
      runner.submitAnswer('E');

      expect(runner.totalAnswered, equals(2));
      expect(runner.correctCount, equals(2));

      // Start over
      runner.start(questionCount: 3);

      expect(runner.totalAnswered, equals(0));
      expect(runner.correctCount, equals(0));
      expect(runner.currentIndex, equals(0));
      expect(runner.isComplete, isFalse);
      expect(runner.results, isEmpty);
    });

    test('currentScore is 0.0 before any answers', () {
      runner.start(questionCount: 3);

      expect(runner.currentScore, equals(0.0));
    });

    test('mixed correct and wrong answers produce correct running score', () {
      runner.start(questionCount: 3);

      runner.submitAnswer('C'); // correct  -> 1/1
      expect(runner.currentScore, equals(1.0));

      runner.submitAnswer('X'); // wrong    -> 1/2
      expect(runner.currentScore, equals(0.5));

      runner.submitAnswer('G'); // correct  -> 2/3
      expect(runner.currentScore, closeTo(2 / 3, 0.001));
    });

    test('results list accumulates every AnswerResult in order', () {
      runner.start(questionCount: 3);

      runner.submitAnswer('C'); // correct
      runner.submitAnswer('X'); // wrong
      runner.submitAnswer('G'); // correct

      final results = runner.results;
      expect(results, hasLength(3));
      expect(results[0].isCorrect, isTrue);
      expect(results[1].isCorrect, isFalse);
      expect(results[2].isCorrect, isTrue);
    });

    test('elapsed duration is non-negative after start', () {
      runner.start(questionCount: 3);

      expect(runner.elapsed, greaterThanOrEqualTo(Duration.zero));
    });
  });
}
