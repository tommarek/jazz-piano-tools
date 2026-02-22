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

    test('all simple intervals have correct semitone values', () {
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

    test('values list contains exactly 12 simple intervals', () {
      expect(Interval.values.length, 12);
    });

    test('fromSemitones returns correct simple interval', () {
      expect(Interval.fromSemitones(0), Interval.unison);
      expect(Interval.fromSemitones(7), Interval.perfectFifth);
      expect(Interval.fromSemitones(12), Interval.unison); // wraps
      expect(Interval.fromSemitones(19), Interval.perfectFifth); // wraps
    });
  });

  group('Compound intervals', () {
    test('compound intervals have correct semitone values', () {
      expect(Interval.octave.semitones, 12);
      expect(Interval.minorNinth.semitones, 13);
      expect(Interval.majorNinth.semitones, 14);
      expect(Interval.augmentedNinth.semitones, 15);
      expect(Interval.perfectEleventh.semitones, 17);
      expect(Interval.sharpEleventh.semitones, 18);
      expect(Interval.minorThirteenth.semitones, 20);
      expect(Interval.majorThirteenth.semitones, 21);
    });

    test('compound intervals are flagged as compound', () {
      for (final interval in Interval.allCompound) {
        expect(interval.isCompound, isTrue,
            reason: '${interval.fullName} should be compound');
      }
    });

    test('simple intervals are not compound', () {
      for (final interval in Interval.allSimple) {
        expect(interval.isCompound, isFalse,
            reason: '${interval.fullName} should not be compound');
      }
    });

    test('simple getter returns octave-equivalent for compound', () {
      expect(Interval.majorNinth.simple, Interval.majorSecond);
      expect(Interval.perfectEleventh.simple, Interval.perfectFourth);
      expect(Interval.majorThirteenth.simple, Interval.majorSixth);
    });

    test('simple getter returns itself for simple intervals', () {
      expect(Interval.majorThird.simple, Interval.majorThird);
      expect(Interval.perfectFifth.simple, Interval.perfectFifth);
    });

    test('all list contains both simple and compound', () {
      expect(Interval.all.length, 20);
      expect(Interval.allSimple.length, 12);
      expect(Interval.allCompound.length, 8);
    });

    test('compound symbols are correct', () {
      expect(Interval.majorNinth.symbol, 'M9');
      expect(Interval.perfectEleventh.symbol, 'P11');
      expect(Interval.sharpEleventh.symbol, '#11');
      expect(Interval.majorThirteenth.symbol, 'M13');
    });
  });
}
