import 'pitch_class.dart';

class Scale {
  final String name;
  final List<int> semitonePattern;

  const Scale(this.name, this.semitonePattern);

  List<PitchClass> build(PitchClass root) {
    return semitonePattern.map((s) => root.transpose(s)).toList();
  }

  static const major = Scale('Major', [0, 2, 4, 5, 7, 9, 11]);
  static const dorian = Scale('Dorian', [0, 2, 3, 5, 7, 9, 10]);
  static const mixolydian = Scale('Mixolydian', [0, 2, 4, 5, 7, 9, 10]);
  static const melodicMinor = Scale('Melodic Minor', [0, 2, 3, 5, 7, 9, 11]);
  static const harmonicMinor = Scale('Harmonic Minor', [0, 2, 3, 5, 7, 8, 11]);
  static const blues = Scale('Blues', [0, 3, 5, 6, 7, 10]);
  static const diminishedWholeTone = Scale(
    'Diminished Whole Tone',
    [0, 1, 3, 4, 6, 8, 10],
  );
  static const wholeTone = Scale('Whole Tone', [0, 2, 4, 6, 8, 10]);
  static const bebopDominant = Scale(
    'Bebop Dominant',
    [0, 2, 4, 5, 7, 9, 10, 11],
  );
}
