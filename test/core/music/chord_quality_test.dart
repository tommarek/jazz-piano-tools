import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/core/music/chord_quality.dart';
import 'package:jazz_piano_tools/core/music/pitch_class.dart';

void main() {
  group('ChordQuality', () {
    test('major triad from C', () {
      final notes = ChordQuality.major.build(PitchClass.c);
      expect(notes.map((n) => n.value).toList(), [0, 4, 7]);
    });

    test('major triad from F#', () {
      final notes = ChordQuality.major.build(PitchClass.fSharp);
      expect(notes.map((n) => n.value).toList(), [6, 10, 1]);
    });

    test('major triad from Bb', () {
      final notes = ChordQuality.major.build(PitchClass(10));
      expect(notes.map((n) => n.value).toList(), [10, 2, 5]);
    });

    test('minor triad from A', () {
      final notes = ChordQuality.minor.build(PitchClass.a);
      expect(notes.map((n) => n.value).toList(), [9, 0, 4]);
    });

    test('major7 from C', () {
      final notes = ChordQuality.major7.build(PitchClass.c);
      expect(notes.map((n) => n.value).toList(), [0, 4, 7, 11]);
    });

    test('minor7 from D', () {
      final notes = ChordQuality.minor7.build(PitchClass.d);
      expect(notes.map((n) => n.value).toList(), [2, 5, 9, 0]);
    });

    test('dominant7 from G', () {
      final notes = ChordQuality.dominant7.build(PitchClass.g);
      expect(notes.map((n) => n.value).toList(), [7, 11, 2, 5]);
    });

    test('halfDiminished from B', () {
      final notes = ChordQuality.halfDiminished.build(PitchClass.b);
      expect(notes.map((n) => n.value).toList(), [11, 2, 5, 9]);
    });

    test('diminished7 from C#', () {
      final notes = ChordQuality.diminished7.build(PitchClass.cSharp);
      expect(notes.map((n) => n.value).toList(), [1, 4, 7, 10]);
    });

    test('augmented from C', () {
      final notes = ChordQuality.augmented.build(PitchClass.c);
      expect(notes.map((n) => n.value).toList(), [0, 4, 8]);
    });

    test('triads have 3 notes', () {
      expect(ChordQuality.major.build(PitchClass.c).length, 3);
      expect(ChordQuality.minor.build(PitchClass.c).length, 3);
      expect(ChordQuality.augmented.build(PitchClass.c).length, 3);
    });

    test('seventh chords have 4 notes', () {
      expect(ChordQuality.major7.build(PitchClass.c).length, 4);
      expect(ChordQuality.minor7.build(PitchClass.c).length, 4);
      expect(ChordQuality.dominant7.build(PitchClass.c).length, 4);
      expect(ChordQuality.halfDiminished.build(PitchClass.c).length, 4);
      expect(ChordQuality.diminished7.build(PitchClass.c).length, 4);
    });

    test('allQualities contains all 8 qualities', () {
      expect(ChordQuality.allQualities.length, 8);
    });
  });
}
