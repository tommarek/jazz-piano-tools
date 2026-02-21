import 'answer_checker.dart';

class ChordNameAnswerChecker extends AnswerChecker<String, String> {
  // Contract long forms to short canonical forms
  static final _contractions = {
    'major': 'maj',
    'minor': 'min',
    'dominant': 'dom',
    'diminished': 'dim',
  };

  @override
  AnswerResult check(String expected, String actual) {
    final normalizedExpected = _normalize(expected);
    final normalizedActual = _normalize(actual);

    if (normalizedExpected == normalizedActual) {
      return const AnswerResult(isCorrect: true, score: 1.0);
    }

    return AnswerResult(
      isCorrect: false,
      score: 0.0,
      feedback: 'Expected: $expected',
    );
  }

  String _normalize(String input) {
    var result = input.toLowerCase().trim();
    _contractions.forEach((full, short) {
      result = result.replaceAll(full, short);
    });
    return result;
  }
}
