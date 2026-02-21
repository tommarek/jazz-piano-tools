class PitchClass {
  final int value;

  PitchClass(int v) : value = v % 12;

  static final c = PitchClass(0);
  static final cSharp = PitchClass(1);
  static final d = PitchClass(2);
  static final dSharp = PitchClass(3);
  static final e = PitchClass(4);
  static final f = PitchClass(5);
  static final fSharp = PitchClass(6);
  static final g = PitchClass(7);
  static final gSharp = PitchClass(8);
  static final a = PitchClass(9);
  static final aSharp = PitchClass(10);
  static final b = PitchClass(11);

  static const _sharpNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  PitchClass transpose(int semitones) => PitchClass(value + semitones);

  int intervalTo(PitchClass other) => (other.value - value) % 12;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PitchClass && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => _sharpNames[value];
}
