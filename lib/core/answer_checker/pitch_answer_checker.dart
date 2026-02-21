import '../music/note_name.dart';
import '../music/pitch_class.dart';
import 'answer_checker.dart';

class PitchSetAnswerChecker
    extends AnswerChecker<Set<PitchClass>, Set<PitchClass>> {
  @override
  AnswerResult check(Set<PitchClass> expected, Set<PitchClass> actual) {
    final missing = expected.difference(actual);
    final extra = actual.difference(expected);

    if (missing.isEmpty && extra.isEmpty) {
      return const AnswerResult(isCorrect: true, score: 1.0);
    }

    final parts = <String>[];
    if (missing.isNotEmpty) {
      final names = missing.map((p) => NoteName.toSharp(p)).join(', ');
      parts.add('Missing: $names');
    }
    if (extra.isNotEmpty) {
      final names = extra.map((p) => NoteName.toSharp(p)).join(', ');
      parts.add('Extra: $names');
    }

    return AnswerResult(
      isCorrect: false,
      score: 0.0,
      feedback: parts.join('. '),
      details: {
        'missing': missing.map((p) => p.value).toList(),
        'extra': extra.map((p) => p.value).toList(),
      },
    );
  }
}
