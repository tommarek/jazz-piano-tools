import 'interval.dart';
import 'pitch_class.dart';

class ChordQuality {
  final String name;
  final String symbol;
  final List<Interval> intervals;

  const ChordQuality(this.name, this.symbol, this.intervals);

  List<PitchClass> build(PitchClass root) {
    return [
      root,
      ...intervals.map((i) => root.transpose(i.semitones)),
    ];
  }

  static const major = ChordQuality('Major', '', [
    Interval.majorThird,
    Interval.perfectFifth,
  ]);

  static const minor = ChordQuality('Minor', 'm', [
    Interval.minorThird,
    Interval.perfectFifth,
  ]);

  static const dominant7 = ChordQuality('Dominant 7th', '7', [
    Interval.majorThird,
    Interval.perfectFifth,
    Interval.minorSeventh,
  ]);

  static const major7 = ChordQuality('Major 7th', 'maj7', [
    Interval.majorThird,
    Interval.perfectFifth,
    Interval.majorSeventh,
  ]);

  static const minor7 = ChordQuality('Minor 7th', 'm7', [
    Interval.minorThird,
    Interval.perfectFifth,
    Interval.minorSeventh,
  ]);

  static const halfDiminished = ChordQuality('Half-Diminished', 'm7b5', [
    Interval.minorThird,
    Interval.tritone,
    Interval.minorSeventh,
  ]);

  static const diminished7 = ChordQuality('Diminished 7th', 'dim7', [
    Interval.minorThird,
    Interval.tritone,
    Interval.majorSixth,
  ]);

  static const augmented = ChordQuality('Augmented', 'aug', [
    Interval.majorThird,
    Interval.minorSixth,
  ]);

  static const allQualities = [
    major, minor, dominant7, major7, minor7, halfDiminished, diminished7,
    augmented,
  ];
}
