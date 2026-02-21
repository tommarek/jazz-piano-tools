import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/core/answer_checker/chord_answer_checker.dart';

void main() {
  late ChordNameAnswerChecker checker;

  setUp(() {
    checker = ChordNameAnswerChecker();
  });

  group('ChordNameAnswerChecker', () {
    test('exact match', () {
      final result = checker.check('Cmaj7', 'Cmaj7');
      expect(result.isCorrect, isTrue);
    });

    test('case insensitive', () {
      final result = checker.check('Cmaj7', 'cmaj7');
      expect(result.isCorrect, isTrue);
    });

    test('alias expansion', () {
      final result = checker.check('Cmajor7', 'Cmaj7');
      expect(result.isCorrect, isTrue);
    });

    test('whitespace handling', () {
      final result = checker.check('Dm7', '  Dm7  ');
      expect(result.isCorrect, isTrue);
    });

    test('wrong answer', () {
      final result = checker.check('Cmaj7', 'Cm7');
      expect(result.isCorrect, isFalse);
      expect(result.feedback, isNotNull);
    });
  });
}
