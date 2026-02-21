import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/core/music/interval.dart';
import 'package:jazz_piano_tools/core/music/pitch_class.dart';

void main() {
  group('Interval', () {
    test('between returns correct intervals from C', () {
      expect(Interval.between(PitchClass.c, PitchClass.c), Interval.unison);
      expect(
        Interval.between(PitchClass.c, PitchClass.cSharp),
        Interval.minorSecond,
      );
      expect(Interval.between(PitchClass.c, PitchClass.d), Interval.majorSecond);
      expect(
        Interval.between(PitchClass.c, PitchClass.dSharp),
        Interval.minorThird,
      );
      expect(Interval.between(PitchClass.c, PitchClass.e), Interval.majorThird);
      expect(
        Interval.between(PitchClass.c, PitchClass.f),
        Interval.perfectFourth,
      );
      expect(
        Interval.between(PitchClass.c, PitchClass.fSharp),
        Interval.tritone,
      );
      expect(
        Interval.between(PitchClass.c, PitchClass.g),
        Interval.perfectFifth,
      );
      expect(
        Interval.between(PitchClass.c, PitchClass.gSharp),
        Interval.minorSixth,
      );
      expect(Interval.between(PitchClass.c, PitchClass.a), Interval.majorSixth);
      expect(
        Interval.between(PitchClass.c, PitchClass.aSharp),
        Interval.minorSeventh,
      );
      expect(
        Interval.between(PitchClass.c, PitchClass.b),
        Interval.majorSeventh,
      );
    });

    test('between works with non-C roots', () {
      expect(
        Interval.between(PitchClass.g, PitchClass.b),
        Interval.majorThird,
      );
      expect(
        Interval.between(PitchClass.d, PitchClass.a),
        Interval.perfectFifth,
      );
    });

    test('inversion of perfect intervals', () {
      expect(Interval.perfectFourth.inversion, Interval.perfectFifth);
      expect(Interval.perfectFifth.inversion, Interval.perfectFourth);
    });

    test('inversion of major/minor intervals', () {
      expect(Interval.majorThird.inversion, Interval.minorSixth);
      expect(Interval.minorThird.inversion, Interval.majorSixth);
      expect(Interval.majorSecond.inversion, Interval.minorSeventh);
      expect(Interval.minorSecond.inversion, Interval.majorSeventh);
    });

    test('unison inverts to unison', () {
      expect(Interval.unison.inversion, Interval.unison);
    });

    test('tritone inverts to tritone', () {
      expect(Interval.tritone.inversion, Interval.tritone);
    });

    test('all intervals have correct semitone values', () {
      for (var i = 0; i < Interval.values.length; i++) {
        expect(Interval.values[i].semitones, i);
      }
    });

    test('symbols are correct', () {
      expect(Interval.unison.symbol, 'P1');
      expect(Interval.majorThird.symbol, 'M3');
      expect(Interval.perfectFifth.symbol, 'P5');
      expect(Interval.minorSeventh.symbol, 'm7');
    });
  });
}
