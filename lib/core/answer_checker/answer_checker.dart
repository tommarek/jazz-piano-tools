class AnswerResult {
  final bool isCorrect;
  final double score;
  final String? feedback;
  final Map<String, dynamic> details;

  const AnswerResult({
    required this.isCorrect,
    required this.score,
    this.feedback,
    this.details = const {},
  });
}

abstract class AnswerChecker<TExpected, TActual> {
  AnswerResult check(TExpected expected, TActual actual);
}
