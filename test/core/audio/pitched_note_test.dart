import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/core/audio/pitched_note.dart';
import 'package:jazz_piano_tools/core/music/pitch_class.dart';

void main() {
  group('PitchedNote', () {
    test('middle C (C4) has MIDI number 60', () {
      final note = PitchedNote(PitchClass.c, 4);
      expect(note.midiNumber, 60);
    });

    test('A4 has MIDI number 69', () {
      final note = PitchedNote(PitchClass.a, 4);
      expect(note.midiNumber, 69);
    });

    test('C0 has MIDI number 12', () {
      final note = PitchedNote(PitchClass.c, 0);
      expect(note.midiNumber, 12);
    });

    test('transpose up by semitones', () {
      final c4 = PitchedNote(PitchClass.c, 4);
      final e4 = c4.transpose(4); // major 3rd
      expect(e4.pitchClass, PitchClass.e);
      expect(e4.octave, 4);
      expect(e4.midiNumber, 64);
    });

    test('transpose across octave boundary', () {
      final b4 = PitchedNote(PitchClass.b, 4);
      final c5 = b4.transpose(1);
      expect(c5.pitchClass, PitchClass.c);
      expect(c5.octave, 5);
      expect(c5.midiNumber, 72);
    });

    test('transpose down', () {
      final c4 = PitchedNote(PitchClass.c, 4);
      final b3 = c4.transpose(-1);
      expect(b3.pitchClass, PitchClass.b);
      expect(b3.octave, 3);
      expect(b3.midiNumber, 59);
    });

    test('equality based on MIDI number', () {
      final a = PitchedNote(PitchClass.c, 4);
      final b = PitchedNote(PitchClass.c, 4);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality for different octaves', () {
      final a = PitchedNote(PitchClass.c, 4);
      final b = PitchedNote(PitchClass.c, 5);
      expect(a, isNot(equals(b)));
    });
  });
}
