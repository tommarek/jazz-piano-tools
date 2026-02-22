import '../music/pitch_class.dart';

/// Consolidates pitch class extraction/parsing from various answer formats.
class PitchClassParser {
  static const _nameToValue = {
    'C': 0, 'C#': 1, 'Db': 1,
    'D': 2, 'D#': 3, 'Eb': 3,
    'E': 4, 'E#': 5, 'Fb': 4,
    'F': 5, 'F#': 6, 'Gb': 6,
    'G': 7, 'G#': 8, 'Ab': 8,
    'A': 9, 'A#': 10, 'Bb': 10,
    'B': 11, 'B#': 0, 'Cb': 11,
  };

  /// Extracts pitch classes from a dynamic answer value.
  ///
  /// Handles `Set<PitchClass>`, `Set<dynamic>` (filters to PitchClass),
  /// and `String` (parses note names like "C, Eb, G").
  static Set<PitchClass> extract(dynamic answer) {
    if (answer is Set<PitchClass>) return answer;
    if (answer is Set) {
      return answer.whereType<PitchClass>().toSet();
    }
    if (answer is String) {
      return _parseString(answer);
    }
    return const {};
  }

  static Set<PitchClass> _parseString(String answer) {
    return answer
        .split(RegExp(r'[,\s]+'))
        .where((s) => s.isNotEmpty)
        .map((name) {
          final value = _nameToValue[name.trim()];
          return value != null ? PitchClass(value) : null;
        })
        .whereType<PitchClass>()
        .toSet();
  }
}
