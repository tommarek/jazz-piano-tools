import 'pitch_class.dart';

enum Interval {
  unison(0, 'P1', 'Unison'),
  minorSecond(1, 'm2', 'Minor 2nd'),
  majorSecond(2, 'M2', 'Major 2nd'),
  minorThird(3, 'm3', 'Minor 3rd'),
  majorThird(4, 'M3', 'Major 3rd'),
  perfectFourth(5, 'P4', 'Perfect 4th'),
  tritone(6, 'TT', 'Tritone'),
  perfectFifth(7, 'P5', 'Perfect 5th'),
  minorSixth(8, 'm6', 'Minor 6th'),
  majorSixth(9, 'M6', 'Major 6th'),
  minorSeventh(10, 'm7', 'Minor 7th'),
  majorSeventh(11, 'M7', 'Major 7th');

  const Interval(this.semitones, this.symbol, this.fullName);

  final int semitones;
  final String symbol;
  final String fullName;

  static Interval between(PitchClass from, PitchClass to) {
    final distance = from.intervalTo(to);
    return Interval.values[distance];
  }

  Interval get inversion => Interval.values[(12 - semitones) % 12];
}
