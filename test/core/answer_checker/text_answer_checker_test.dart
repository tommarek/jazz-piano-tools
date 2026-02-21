import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/core/answer_checker/text_answer_checker.dart';

void main() {
  late TextAnswerChecker checker;

  setUp(() {
    checker = TextAnswerChecker();
  });

  group('TextAnswerChecker', () {
    test('exact match', () {
      final result = checker.check('F', 'F');
      expect(result.isCorrect, isTrue);
    });

    test('case insensitive', () {
      final result = checker.check('F', 'f');
      expect(result.isCorrect, isTrue);
    });

    test('whitespace trim', () {
      final result = checker.check('Bb', ' Bb ');
      expect(result.isCorrect, isTrue);
    });

    test('wrong answer', () {
      final result = checker.check('C', 'D');
      expect(result.isCorrect, isFalse);
      expect(result.feedback, contains('C'));
    });
  });
}
