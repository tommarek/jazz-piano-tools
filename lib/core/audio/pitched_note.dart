import '../music/pitch_class.dart';

/// A note with a specific pitch class and octave, suitable for MIDI playback.
///
/// Middle C is `PitchedNote(PitchClass.c, 4)` with MIDI number 60.
class PitchedNote {
  final PitchClass pitchClass;
  final int octave;

  const PitchedNote(this.pitchClass, this.octave);

  /// MIDI note number (0–127). Middle C (C4) = 60.
  int get midiNumber => (octave + 1) * 12 + pitchClass.value;

  /// Returns a new [PitchedNote] transposed by [semitones].
  PitchedNote transpose(int semitones) {
    final newMidi = midiNumber + semitones;
    final pc = PitchClass(newMidi % 12);
    final oct = (newMidi ~/ 12) - 1;
    return PitchedNote(pc, oct);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PitchedNote && other.midiNumber == midiNumber;

  @override
  int get hashCode => midiNumber.hashCode;

  @override
  String toString() => '$pitchClass$octave';
}
