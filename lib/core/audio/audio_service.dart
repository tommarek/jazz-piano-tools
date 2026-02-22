import '../music/interval.dart';
import 'pitched_note.dart';

/// Playback mode for audio questions.
enum PlaybackMode {
  melodicAscending,
  melodicDescending,
  harmonic,
  chord,
}

/// Abstract interface for playing musical sounds.
///
/// Implementations may use MIDI (via SoundFont), audio samples, or any
/// other synthesis technique.
abstract class AudioService {
  /// Initializes the audio engine (e.g., loads SoundFont).
  Future<void> init();

  /// Plays a single note for [durationMs] milliseconds.
  Future<void> playNote(PitchedNote note, {int durationMs = 500});

  /// Plays an interval from [root].
  ///
  /// If [harmonic] is true, both notes sound simultaneously.
  /// Otherwise they play sequentially (melodic).
  Future<void> playInterval(
    PitchedNote root,
    Interval interval, {
    bool harmonic = false,
    int durationMs = 500,
  });

  /// Plays a chord (all notes simultaneously).
  Future<void> playChord(
    List<PitchedNote> notes, {
    int durationMs = 800,
  });

  /// Stops all currently playing sounds.
  Future<void> stopAll();

  /// Releases resources.
  Future<void> dispose();
}
