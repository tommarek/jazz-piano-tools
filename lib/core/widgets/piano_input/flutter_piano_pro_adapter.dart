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
  final Set<PitchClass> _activeNotes = {};

  /// Maps pointer IDs to the PitchClass they are currently pressing,
  /// so we can correctly remove notes on pointer-up.
  final Map<int, PitchClass> _pointerNotes = {};

  @override
  void didUpdateWidget(FlutterPianoProAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear toggle state when the question changes (new callback identity).
    if (widget.onNotesChanged != oldWidget.onNotesChanged) {
      _activeNotes.clear();
      _pointerNotes.clear();
    }
  }

  PitchClass _noteModelToPitchClass(NoteModel note) {
    return PitchClass(note.midiNoteNumber % 12);
  }

  Map<int, Color>? _buildButtonColors() {
    if (widget.highlightedNotes.isEmpty && _activeNotes.isEmpty) return null;

    final colors = <int, Color>{};

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

      if (_activeNotes.contains(pc)) {
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

        if (_activeNotes.contains(blackPc)) {
          colors[blackMidi] = Colors.blue.shade300;
        } else if (widget.highlightedNotes.contains(blackPc)) {
          colors[blackMidi] = Colors.amber.shade200;
        }
      }
    }

    return colors.isEmpty ? null : colors;
  }

  void _onTapDown(NoteModel? note, int pointer) {
    if (note == null) return;
    final pc = _noteModelToPitchClass(note);
    setState(() {
      if (_activeNotes.contains(pc)) {
        _activeNotes.remove(pc);
      } else {
        _activeNotes.add(pc);
      }
      _pointerNotes[pointer] = pc;
    });
    widget.onNotesChanged?.call(Set.unmodifiable(_activeNotes));
  }

  void _onTapUpdate(NoteModel? note, int pointer) {
    // No-op for toggle mode — don't change selection on drag
    if (note == null) return;
    _pointerNotes[pointer] = _noteModelToPitchClass(note);
  }

  void _onTapUp(int pointer) {
    _pointerNotes.remove(pointer);
    // Don't remove notes — they stay toggled
  }

  @override
  Widget build(BuildContext context) {
    return PianoPro(
      noteCount: widget.octaveCount * 7,
      firstOctave: widget.startOctave,
      showNames: true,
      showOctave: false,
      expand: true,
      buttonColors: _buildButtonColors(),
      onTapDown: _onTapDown,
      onTapUpdate: _onTapUpdate,
      onTapUp: _onTapUp,
    );
  }
}
