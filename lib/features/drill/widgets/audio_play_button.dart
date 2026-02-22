import 'package:flutter/material.dart';

import '../../../core/audio/audio_service.dart';
import '../runner/exercise_question.dart';

class AudioPlayButton extends StatefulWidget {
  final AudioQuestionData audioData;
  final AudioService audioService;

  const AudioPlayButton({
    required this.audioData,
    required this.audioService,
    super.key,
  });

  @override
  State<AudioPlayButton> createState() => _AudioPlayButtonState();
}

class _AudioPlayButtonState extends State<AudioPlayButton> {
  bool _playing = false;
  bool _hasPlayed = false;

  Future<void> _play() async {
    if (_playing) return;
    setState(() => _playing = true);

    try {
      final data = widget.audioData;
      switch (data.playbackMode) {
        case PlaybackMode.chord:
          await widget.audioService.playChord(data.notes);
        case PlaybackMode.harmonic:
          await widget.audioService.playChord(data.notes);
        case PlaybackMode.melodicAscending:
          for (final note in data.notes) {
            await widget.audioService.playNote(note);
          }
        case PlaybackMode.melodicDescending:
          for (final note in data.notes.reversed) {
            await widget.audioService.playNote(note);
          }
      }
    } finally {
      if (mounted) {
        setState(() {
          _playing = false;
          _hasPlayed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FilledButton.tonalIcon(
      onPressed: _playing ? null : _play,
      icon: Icon(
        _playing ? Icons.volume_up : Icons.play_arrow,
        size: 28,
      ),
      label: Text(
        _playing
            ? 'Playing...'
            : _hasPlayed
                ? 'Replay'
                : 'Play',
        style: theme.textTheme.titleMedium,
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
      ),
    );
  }
}
