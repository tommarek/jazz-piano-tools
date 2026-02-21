import 'package:flutter/material.dart';
import '../../music/pitch_class.dart';

typedef OnNotesChanged = void Function(Set<PitchClass> activeNotes);

abstract class PianoInputWidget extends StatefulWidget {
  final int octaveCount;
  final int startOctave;
  final OnNotesChanged? onNotesChanged;
  final Set<PitchClass> highlightedNotes;

  const PianoInputWidget({
    super.key,
    this.octaveCount = 2,
    this.startOctave = 3,
    this.onNotesChanged,
    this.highlightedNotes = const {},
  });
}
