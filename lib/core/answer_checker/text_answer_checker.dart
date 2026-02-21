import 'answer_checker.dart';

class TextAnswerChecker extends AnswerChecker<String, String> {
  @override
  AnswerResult check(String expected, String actual) {
    final normalizedExpected = expected.toLowerCase().trim();
    final normalizedActual = actual.toLowerCase().trim();

    if (normalizedExpected == normalizedActual) {
      return const AnswerResult(isCorrect: true, score: 1.0);
    }

    return AnswerResult(
      isCorrect: false,
      score: 0.0,
      feedback: 'Expected: $expected',
    );
  }
}
