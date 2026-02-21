import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/core/music/circle_of_fifths.dart';
import 'package:jazz_piano_tools/core/music/pitch_class.dart';

void main() {
  group('CircleOfFifths', () {
    test('fifthsOrder has 12 unique entries', () {
      final order = CircleOfFifths.fifthsOrder;
      expect(order.length, 12);
      expect(order.map((p) => p.value).toSet().length, 12);
    });

    test('fourthsOrder has 12 unique entries', () {
      final order = CircleOfFifths.fourthsOrder;
      expect(order.length, 12);
      expect(order.map((p) => p.value).toSet().length, 12);
    });

    test('fifths are each 7 semitones apart', () {
      final order = CircleOfFifths.fifthsOrder;
      for (var i = 0; i < 11; i++) {
        expect(order[i].intervalTo(order[i + 1]), 7);
      }
    });

    test('fourths are each 5 semitones apart', () {
      final order = CircleOfFifths.fourthsOrder;
      for (var i = 0; i < 11; i++) {
        expect(order[i].intervalTo(order[i + 1]), 5);
      }
    });

    test('fourthsOrder starts C, F, Bb', () {
      final order = CircleOfFifths.fourthsOrder;
      expect(order[0], PitchClass.c);
      expect(order[1], PitchClass.f);
      expect(order[2], PitchClass(10)); // Bb
    });

    test('keySignature returns correct values', () {
      expect(CircleOfFifths.keySignature(PitchClass.c), 0);
      expect(CircleOfFifths.keySignature(PitchClass.g), 1);
      expect(CircleOfFifths.keySignature(PitchClass.d), 2);
      expect(CircleOfFifths.keySignature(PitchClass.a), 3);
      expect(CircleOfFifths.keySignature(PitchClass.f), -1);
      expect(CircleOfFifths.keySignature(PitchClass(10)), -2); // Bb
      expect(CircleOfFifths.keySignature(PitchClass(3)), -3); // Eb
    });
  });
}
