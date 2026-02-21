import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/core/answer_checker/pitch_answer_checker.dart';
import 'package:jazz_piano_tools/core/music/pitch_class.dart';

void main() {
  late PitchSetAnswerChecker checker;

  setUp(() {
    checker = PitchSetAnswerChecker();
  });

  group('PitchSetAnswerChecker', () {
    test('exact match returns correct', () {
      final expected = {PitchClass.c, PitchClass.e, PitchClass.g};
      final actual = {PitchClass.c, PitchClass.e, PitchClass.g};
      final result = checker.check(expected, actual);
      expect(result.isCorrect, isTrue);
      expect(result.score, 1.0);
      expect(result.feedback, isNull);
    });

    test('missing one note', () {
      final expected = {PitchClass.c, PitchClass.e, PitchClass.g};
      final actual = {PitchClass.c, PitchClass.e};
      final result = checker.check(expected, actual);
      expect(result.isCorrect, isFalse);
      expect(result.feedback, contains('Missing'));
      expect(result.feedback, contains('G'));
    });

    test('extra one note', () {
      final expected = {PitchClass.c, PitchClass.e, PitchClass.g};
      final actual = {PitchClass.c, PitchClass.e, PitchClass.g, PitchClass.b};
      final result = checker.check(expected, actual);
      expect(result.isCorrect, isFalse);
      expect(result.feedback, contains('Extra'));
      expect(result.feedback, contains('B'));
    });

    test('completely wrong', () {
      final expected = {PitchClass.c, PitchClass.e, PitchClass.g};
      final actual = {PitchClass.d, PitchClass.fSharp, PitchClass.a};
      final result = checker.check(expected, actual);
      expect(result.isCorrect, isFalse);
      expect(result.feedback, contains('Missing'));
      expect(result.feedback, contains('Extra'));
    });

    test('empty actual', () {
      final expected = {PitchClass.c, PitchClass.e, PitchClass.g};
      final actual = <PitchClass>{};
      final result = checker.check(expected, actual);
      expect(result.isCorrect, isFalse);
    });

    test('enharmonic equivalence via PitchClass', () {
      // C# and Db are both PitchClass(1)
      final expected = {PitchClass(1)};
      final actual = {PitchClass(1)}; // Same PitchClass regardless of spelling
      final result = checker.check(expected, actual);
      expect(result.isCorrect, isTrue);
    });
  });
}
