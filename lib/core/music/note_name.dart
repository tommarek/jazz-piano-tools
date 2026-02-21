import 'pitch_class.dart';

class NoteName {
  static const sharpNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  static const flatNames = [
    'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B',
  ];

  static const _letterValues = {
    'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11,
  };

  static PitchClass parse(String name) {
    final upper = name.trim().toUpperCase();
    if (upper.isEmpty) {
      throw ArgumentError('Empty note name');
    }

    final letter = upper[0];
    final base = _letterValues[letter];
    if (base == null) {
      throw ArgumentError('Invalid note letter: $letter');
    }

    var offset = 0;
    for (var i = 1; i < upper.length; i++) {
      switch (upper[i]) {
        case '#':
          offset++;
        case 'B':
          offset--;
        default:
          throw ArgumentError('Invalid accidental: ${upper[i]}');
      }
    }

    return PitchClass(base + offset);
  }

  static String toSharp(PitchClass pc) => sharpNames[pc.value];
  static String toFlat(PitchClass pc) => flatNames[pc.value];
}
