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
          break;
        case 'B':
          offset--;
          break;
        default:
          throw ArgumentError('Invalid accidental: ${upper[i]}');
      }
    }

    return PitchClass(base + offset);
  }

  static String toSharp(PitchClass pc) => sharpNames[pc.value];
  static String toFlat(PitchClass pc) => flatNames[pc.value];

  /// Pitch classes whose key signatures use flats: Db, Eb, F, Gb, Ab, Bb.
  static const _flatRoots = {1, 3, 5, 6, 8, 10};

  /// Returns a namer appropriate for the given root's key signature.
  ///
  /// Flat-key roots (Db, Eb, F, Ab, Bb) use [toFlat]; all others use [toSharp].
  static String Function(PitchClass) namerForRoot(PitchClass root) {
    return _flatRoots.contains(root.value) ? toFlat : toSharp;
  }

  /// Returns a note naming function for the given style.
  ///
  /// - `'sharp'` -> [toSharp]
  /// - `'flat'` -> [toFlat]
  /// - `'auto'` or `null` -> returns `null` (caller should use [namerForRoot])
  static String Function(PitchClass)? namerForStyle(String? style) {
    return switch (style) {
      'sharp' => toSharp,
      'flat' => toFlat,
      _ => null,
    };
  }
}
