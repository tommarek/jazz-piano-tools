import 'pitch_class.dart';

class CircleOfFifths {
  static List<PitchClass> get fifthsOrder {
    final result = <PitchClass>[];
    var current = PitchClass.c;
    for (var i = 0; i < 12; i++) {
      result.add(current);
      current = current.transpose(7);
    }
    return result;
  }

  static List<PitchClass> get fourthsOrder {
    final result = <PitchClass>[];
    var current = PitchClass.c;
    for (var i = 0; i < 12; i++) {
      result.add(current);
      current = current.transpose(5);
    }
    return result;
  }

  /// Returns the number of sharps (positive) or flats (negative) in the key.
  /// C=0, G=1, D=2, ..., F=-1, Bb=-2, ...
  static int keySignature(PitchClass root) {
    // Position in circle of fifths from C
    final fifths = fifthsOrder;
    for (var i = 0; i < 12; i++) {
      if (fifths[i] == root) {
        // 0..6 are sharps, 7..11 map to -5..-1 flats
        return i <= 6 ? i : i - 12;
      }
    }
    return 0;
  }
}
