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
      // Black keys sit at noteIndex 1,2,4,5,6 (Db, Eb, Gb, Ab, Bb).
      if (noteIndex != 0 && noteIndex != 3) {
        final blackNote = NoteModel(
          name: '',
          octave: octave,
          noteIndex: noteIndex,
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
      _activeNotes.add(pc);
      _pointerNotes[pointer] = pc;
    });
    widget.onNotesChanged?.call(Set.unmodifiable(_activeNotes));
  }

  void _onTapUpdate(NoteModel? note, int pointer) {
    if (note == null) return;
    final pc = _noteModelToPitchClass(note);
    final previousPc = _pointerNotes[pointer];
    if (previousPc == pc) return;

    setState(() {
      // Remove the previous note for this pointer if no other pointer holds it.
      if (previousPc != null) {
        final stillHeld =
            _pointerNotes.entries.any((e) => e.key != pointer && e.value == previousPc);
        if (!stillHeld) {
          _activeNotes.remove(previousPc);
        }
      }
      _activeNotes.add(pc);
      _pointerNotes[pointer] = pc;
    });
    widget.onNotesChanged?.call(Set.unmodifiable(_activeNotes));
  }

  void _onTapUp(int pointer) {
    final pc = _pointerNotes.remove(pointer);
    if (pc == null) return;

    setState(() {
      // Only remove the note if no other pointer is still holding it.
      final stillHeld = _pointerNotes.values.contains(pc);
      if (!stillHeld) {
        _activeNotes.remove(pc);
      }
    });
    widget.onNotesChanged?.call(Set.unmodifiable(_activeNotes));
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
