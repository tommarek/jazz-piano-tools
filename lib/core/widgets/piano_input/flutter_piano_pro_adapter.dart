import 'package:flutter/material.dart';
import 'package:flutter_piano_pro/flutter_piano_pro.dart';
import 'package:flutter_piano_pro/note_model.dart';

import '../../music/pitch_class.dart';
import 'piano_input_widget.dart';

/// Adapter that wraps PianoPro from the flutter_piano_pro package
/// and translates note events into [PitchClass] callbacks.
class FlutterPianoProAdapter extends PianoInputWidget {
  const FlutterPianoProAdapter({
    super.key,
    super.octaveCount,
    super.startOctave,
    super.onNotesChanged,
    super.highlightedNotes,
  });

  @override
  State<FlutterPianoProAdapter> createState() =>
      _FlutterPianoProAdapterState();
}

class _FlutterPianoProAdapterState extends State<FlutterPianoProAdapter> {
  final Set<int> _activeMidis = {};

  /// Maps pointer IDs to the MIDI note number they are currently pressing,
  /// so we can correctly remove notes on pointer-up.
  final Map<int, int> _pointerNotes = {};

  @override
  void didUpdateWidget(FlutterPianoProAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear toggle state when the question changes (new callback identity).
    if (widget.onNotesChanged != oldWidget.onNotesChanged) {
      _activeMidis.clear();
      _pointerNotes.clear();
    }
  }

  PitchClass _noteModelToPitchClass(NoteModel note) {
    return PitchClass(note.midiNoteNumber % 12);
  }

  Map<int, Color>? _buildButtonColors() {
    final colors = <int, Color>{};
    final whiteBase = const Color(0xFFF7F7F7);
    final blackBase = const Color(0xFF1E1E1E);

    // Highlight notes across all visible octaves.
    final totalWhiteKeys = widget.octaveCount * 7;
    for (var i = 0; i < totalWhiteKeys; i++) {
      final noteIndex = (i + 0) % 7; // firstNoteIndex is always 0 (C)
      final octave =
          widget.startOctave + (i ~/ 7);
      final whiteNote = NoteModel(
        name: '',
        octave: octave,
        noteIndex: noteIndex,
        isFlat: false,
      );
      final midi = whiteNote.midiNoteNumber;
      final pc = PitchClass(midi % 12);

      colors[midi] = whiteBase;
      if (_activeMidis.contains(midi)) {
        colors[midi] = Colors.blue.shade300;
      } else if (widget.highlightedNotes.contains(pc)) {
        colors[midi] = Colors.amber.shade200;
      }

      // Check the flat/sharp variant above this white key if applicable.
      // White keys with a black key above: C(0), D(1), F(3), G(4), A(5).
      // E(2) and B(6) have no sharp/black key above them.
      if (noteIndex != 2 && noteIndex != 6) {
        final blackNote = NoteModel(
          name: '',
          octave: octave,
          noteIndex: noteIndex + 1,
          isFlat: true,
        );
        final blackMidi = blackNote.midiNoteNumber;
        final blackPc = PitchClass(blackMidi % 12);

        colors[blackMidi] = blackBase;
        if (_activeMidis.contains(blackMidi)) {
          colors[blackMidi] = Colors.blue.shade300;
        } else if (widget.highlightedNotes.contains(blackPc)) {
          colors[blackMidi] = Colors.amber.shade200;
        }
      }
    }

    return colors;
  }

  void _onTapDown(NoteModel? note, int pointer) {
    if (note == null) return;
    final midi = note.midiNoteNumber;
    final pc = _noteModelToPitchClass(note);
    setState(() {
      if (_activeMidis.contains(midi)) {
        _activeMidis.remove(midi);
      } else {
        _activeMidis.add(midi);
      }
      _pointerNotes[pointer] = midi;
    });
    final pcs = _activeMidis
        .map((m) => PitchClass(m % 12))
        .toSet();
    widget.onNotesChanged?.call(Set.unmodifiable(pcs));
  }

  void _onTapUpdate(NoteModel? note, int pointer) {
    // No-op for toggle mode — don't change selection on drag
    if (note == null) return;
    _pointerNotes[pointer] = note.midiNoteNumber;
  }

  void _onTapUp(int pointer) {
    _pointerNotes.remove(pointer);
    // Don't remove notes — they stay toggled
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF2B2B2B),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: PianoPro(
          noteCount: widget.octaveCount * 7,
          firstOctave: widget.startOctave,
          showNames: true,
          showOctave: false,
          expand: true,
          whiteHeight: 140,
          blackWidthRatio: 2.0,
          buttonColors: _buildButtonColors(),
          onTapDown: _onTapDown,
          onTapUpdate: _onTapUpdate,
          onTapUp: _onTapUp,
        ),
      ),
    );
  }
}
