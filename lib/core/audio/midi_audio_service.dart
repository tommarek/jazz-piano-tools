import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:flutter/foundation.dart';

import '../music/interval.dart';
import 'audio_service.dart';
import 'pitched_note.dart';

/// [AudioService] implementation using flutter_midi_pro and a SoundFont file.
class MidiAudioService implements AudioService {
  final MidiPro _midi = MidiPro();
  bool _initialized = false;
  Future<void>? _initFuture;
  Object? _lastInitError;

  static const _velocity = 100;

  @override
  Future<void> init() async {
    if (_initialized) return;
    if (_initFuture != null) {
      await _initFuture;
      return;
    }

    _initFuture = () async {
      try {
        await _midi.loadSoundfont(sf2Path: 'assets/soundfonts/piano.sf2');
        _initialized = true;
        _lastInitError = null;
        // Give Android/emulator audio a moment after synth init to become audible.
        await Future<void>.delayed(const Duration(milliseconds: 40));
      } catch (e, st) {
        // Audio may not be available in tests/web, but don't fail silently.
        _initialized = false;
        _lastInitError = e;
        debugPrint('MidiAudioService.init failed: $e');
        debugPrint('$st');
      } finally {
        _initFuture = null;
      }
    }();

    await _initFuture;
  }

  @override
  Future<void> playNote(PitchedNote note, {int durationMs = 500}) async {
    await init();
    if (!_initialized) {
      debugPrint('MidiAudioService.playNote skipped (not initialized): $_lastInitError');
      return;
    }
    final midi = note.midiNumber.clamp(0, 127);
    try {
      await _midi.playMidiNote(midi: midi, velocity: _velocity);
      await Future<void>.delayed(Duration(milliseconds: durationMs));
      await _midi.stopMidiNote(midi: midi);
    } catch (e, st) {
      debugPrint('MidiAudioService.playNote failed (midi=$midi): $e');
      debugPrint('$st');
      _initialized = false;
    }
  }

  @override
  Future<void> playInterval(
    PitchedNote root,
    Interval interval, {
    bool harmonic = false,
    int durationMs = 500,
  }) async {
    await init();
    if (!_initialized) return;
    final second = root.transpose(interval.semitones);

    if (harmonic) {
      await playChord([root, second], durationMs: durationMs);
    } else {
      await playNote(root, durationMs: durationMs);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await playNote(second, durationMs: durationMs);
    }
  }

  @override
  Future<void> playChord(
    List<PitchedNote> notes, {
    int durationMs = 800,
  }) async {
    await init();
    if (!_initialized) {
      debugPrint('MidiAudioService.playChord skipped (not initialized): $_lastInitError');
      return;
    }
    for (final note in notes) {
      final midi = note.midiNumber.clamp(0, 127);
      await _midi.playMidiNote(midi: midi, velocity: _velocity);
    }
    await Future<void>.delayed(Duration(milliseconds: durationMs));
    for (final note in notes) {
      final midi = note.midiNumber.clamp(0, 127);
      await _midi.stopMidiNote(midi: midi);
    }
  }

  @override
  Future<void> stopAll() async {
    if (!_initialized) return;
    try {
      await _midi.stopAllMidiNotes();
    } catch (e) {
      debugPrint('MidiAudioService.stopAll failed: $e');
      _initialized = false;
    }
  }

  @override
  Future<void> dispose() async {
    if (!_initialized) return;
    await stopAll();
    try {
      await _midi.dispose();
    } catch (_) {
      // Ignore dispose failures.
    } finally {
      _initialized = false;
    }
  }
}
