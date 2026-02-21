import 'note_name.dart';
import 'pitch_class.dart';

class Enharmonic {
  static bool areEquivalent(String a, String b) {
    return NoteName.parse(a) == NoteName.parse(b);
  }

  static List<String> spellings(PitchClass pc) {
    final result = <String>{};
    result.add(NoteName.toSharp(pc));
    result.add(NoteName.toFlat(pc));

    // Add common enharmonic names
    const extras = {
      0: ['B#'],
      1: ['C#', 'Db'],
      3: ['D#', 'Eb'],
      4: ['Fb'],
      5: ['E#'],
      6: ['F#', 'Gb'],
      8: ['G#', 'Ab'],
      10: ['A#', 'Bb'],
      11: ['Cb'],
    };

    final extra = extras[pc.value];
    if (extra != null) {
      result.addAll(extra);
    }

    return result.toList();
  }
}
