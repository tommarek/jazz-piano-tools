import 'pitch_class.dart';

/// Represents a musical interval — the distance between two pitches.
///
/// All 12 simple intervals (within an octave) are provided as static constants,
/// plus compound intervals (9th, 11th, 13th) used in extended jazz harmony.
class Interval {
  final int semitones;
  final String symbol;
  final String fullName;
  final bool isCompound;

  const Interval(this.semitones, this.symbol, this.fullName,
      {this.isCompound = false});

  // ── Simple intervals (0–11 semitones) ──────────────────────────────

  static const unison = Interval(0, 'P1', 'Unison');
  static const minorSecond = Interval(1, 'm2', 'Minor 2nd');
  static const majorSecond = Interval(2, 'M2', 'Major 2nd');
  static const minorThird = Interval(3, 'm3', 'Minor 3rd');
  static const majorThird = Interval(4, 'M3', 'Major 3rd');
  static const perfectFourth = Interval(5, 'P4', 'Perfect 4th');
  static const tritone = Interval(6, 'TT', 'Tritone');
  static const diminishedFifth = Interval(6, 'dim5', 'Diminished 5th');
  static const perfectFifth = Interval(7, 'P5', 'Perfect 5th');
  static const augmentedFifth = Interval(8, 'aug5', 'Augmented 5th');
  static const minorSixth = Interval(8, 'm6', 'Minor 6th');
  static const diminishedSeventh = Interval(9, 'dim7', 'Diminished 7th');
  static const majorSixth = Interval(9, 'M6', 'Major 6th');
  static const minorSeventh = Interval(10, 'm7', 'Minor 7th');
  static const majorSeventh = Interval(11, 'M7', 'Major 7th');

  // ── Compound intervals (12+ semitones) ─────────────────────────────

  static const octave =
      Interval(12, 'P8', 'Octave', isCompound: true);
  static const minorNinth =
      Interval(13, 'm9', 'Minor 9th', isCompound: true);
  static const majorNinth =
      Interval(14, 'M9', 'Major 9th', isCompound: true);
  static const augmentedNinth =
      Interval(15, '#9', 'Augmented 9th', isCompound: true);
  static const perfectEleventh =
      Interval(17, 'P11', 'Perfect 11th', isCompound: true);
  static const sharpEleventh =
      Interval(18, '#11', 'Sharp 11th', isCompound: true);
  static const minorThirteenth =
      Interval(20, 'm13', 'Minor 13th', isCompound: true);
  static const majorThirteenth =
      Interval(21, 'M13', 'Major 13th', isCompound: true);

  // ── Lists ──────────────────────────────────────────────────────────

  /// The 12 simple intervals (P1 through M7), indexed by semitone count.
  /// `values[0]` = unison, `values[11]` = majorSeventh.
  static const values = [
    unison, minorSecond, majorSecond, minorThird,
    majorThird, perfectFourth, tritone, perfectFifth,
    minorSixth, majorSixth, minorSeventh, majorSeventh,
  ];

  /// All simple intervals (same as [values]).
  static const allSimple = values;

  /// All compound intervals.
  static const allCompound = [
    octave, minorNinth, majorNinth, augmentedNinth,
    perfectEleventh, sharpEleventh,
    minorThirteenth, majorThirteenth,
  ];

  /// All intervals, simple and compound.
  static const all = [
    ...values,
    ...allCompound,
  ];

  // ── Factories ──────────────────────────────────────────────────────

  /// Returns the simple interval for the given semitone distance (mod 12).
  static Interval fromSemitones(int semitones) {
    return values[semitones % 12];
  }

  /// Returns the simple interval between two pitch classes.
  static Interval between(PitchClass from, PitchClass to) {
    final distance = from.intervalTo(to);
    return values[distance];
  }

  // ── Properties ─────────────────────────────────────────────────────

  /// The simple (within-octave) equivalent of this interval.
  /// For simple intervals, returns itself.
  Interval get simple => isCompound ? values[semitones % 12] : this;

  /// The inversion of this simple interval within an octave.
  Interval get inversion => values[(12 - semitones % 12) % 12];

  // ── Object overrides ───────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Interval && other.semitones == semitones;

  @override
  int get hashCode => semitones.hashCode;

  @override
  String toString() => '$fullName ($symbol)';
}
