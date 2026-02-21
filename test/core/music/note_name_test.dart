import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/core/music/note_name.dart';
import 'package:jazz_piano_tools/core/music/pitch_class.dart';

void main() {
  group('NoteName', () {
    test('parses natural notes', () {
      expect(NoteName.parse('C'), PitchClass.c);
      expect(NoteName.parse('D'), PitchClass.d);
      expect(NoteName.parse('E'), PitchClass.e);
      expect(NoteName.parse('F'), PitchClass.f);
      expect(NoteName.parse('G'), PitchClass.g);
      expect(NoteName.parse('A'), PitchClass.a);
      expect(NoteName.parse('B'), PitchClass.b);
    });

    test('parses sharps', () {
      expect(NoteName.parse('C#'), PitchClass(1));
      expect(NoteName.parse('F#'), PitchClass(6));
      expect(NoteName.parse('G#'), PitchClass(8));
    });

    test('parses flats', () {
      expect(NoteName.parse('Db'), PitchClass(1));
      expect(NoteName.parse('Eb'), PitchClass(3));
      expect(NoteName.parse('Bb'), PitchClass(10));
      expect(NoteName.parse('Ab'), PitchClass(8));
      expect(NoteName.parse('Gb'), PitchClass(6));
    });

    test('parses double sharp', () {
      expect(NoteName.parse('C##'), PitchClass(2));
      expect(NoteName.parse('F##'), PitchClass(7));
    });

    test('parses double flat', () {
      expect(NoteName.parse('Dbb'), PitchClass(0));
      expect(NoteName.parse('Ebb'), PitchClass(2));
    });

    test('is case insensitive', () {
      expect(NoteName.parse('c#'), PitchClass(1));
      expect(NoteName.parse('db'), PitchClass(1));
      expect(NoteName.parse('f'), PitchClass(5));
    });

    test('handles whitespace', () {
      expect(NoteName.parse(' C# '), PitchClass(1));
    });

    test('toSharp returns correct names', () {
      expect(NoteName.toSharp(PitchClass(0)), 'C');
      expect(NoteName.toSharp(PitchClass(1)), 'C#');
      expect(NoteName.toSharp(PitchClass(6)), 'F#');
    });

    test('toFlat returns correct names', () {
      expect(NoteName.toFlat(PitchClass(1)), 'Db');
      expect(NoteName.toFlat(PitchClass(3)), 'Eb');
      expect(NoteName.toFlat(PitchClass(10)), 'Bb');
    });

    test('sharp and flat roundtrip', () {
      for (var i = 0; i < 12; i++) {
        final pc = PitchClass(i);
        expect(NoteName.parse(NoteName.toSharp(pc)), pc);
        expect(NoteName.parse(NoteName.toFlat(pc)), pc);
      }
    });

    test('throws on invalid input', () {
      expect(() => NoteName.parse(''), throwsArgumentError);
      expect(() => NoteName.parse('X'), throwsArgumentError);
    });
  });
}
