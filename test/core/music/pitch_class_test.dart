import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/core/music/pitch_class.dart';

void main() {
  group('PitchClass', () {
    test('constructor wraps values mod 12', () {
      expect(PitchClass(14).value, 2);
      expect(PitchClass(12).value, 0);
      expect(PitchClass(0).value, 0);
      expect(PitchClass(11).value, 11);
    });

    test('handles negative values', () {
      expect(PitchClass(-1).value, 11);
      expect(PitchClass(-12).value, 0);
    });

    test('named constants have correct values', () {
      expect(PitchClass.c.value, 0);
      expect(PitchClass.cSharp.value, 1);
      expect(PitchClass.d.value, 2);
      expect(PitchClass.dSharp.value, 3);
      expect(PitchClass.e.value, 4);
      expect(PitchClass.f.value, 5);
      expect(PitchClass.fSharp.value, 6);
      expect(PitchClass.g.value, 7);
      expect(PitchClass.gSharp.value, 8);
      expect(PitchClass.a.value, 9);
      expect(PitchClass.aSharp.value, 10);
      expect(PitchClass.b.value, 11);
    });

    test('transpose works correctly', () {
      expect(PitchClass.c.transpose(7), PitchClass.g);
      expect(PitchClass.c.transpose(4), PitchClass.e);
      expect(PitchClass.c.transpose(12), PitchClass.c);
    });

    test('transpose wraps at boundary', () {
      expect(PitchClass.b.transpose(2), PitchClass.cSharp);
      expect(PitchClass.a.transpose(5), PitchClass.d);
    });

    test('intervalTo returns ascending semitones', () {
      expect(PitchClass.c.intervalTo(PitchClass.g), 7);
      expect(PitchClass.c.intervalTo(PitchClass.e), 4);
      expect(PitchClass.c.intervalTo(PitchClass.c), 0);
    });

    test('intervalTo wraps correctly', () {
      expect(PitchClass.g.intervalTo(PitchClass.c), 5);
      expect(PitchClass.b.intervalTo(PitchClass.c), 1);
    });

    test('equality works', () {
      expect(PitchClass(0), equals(PitchClass(12)));
      expect(PitchClass(0), equals(PitchClass.c));
      expect(PitchClass(7), equals(PitchClass.g));
      expect(PitchClass(0) == PitchClass(1), isFalse);
    });

    test('toString returns sharp name', () {
      expect(PitchClass.c.toString(), 'C');
      expect(PitchClass.cSharp.toString(), 'C#');
      expect(PitchClass.b.toString(), 'B');
    });
  });
}
