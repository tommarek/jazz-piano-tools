import 'package:flutter/material.dart';

import '../../music/note_name.dart';
import 'notation_renderer.dart';

/// Placeholder adapter for the simple_sheet_music package.
///
/// Displays note names as text. This will be replaced with a full
/// simple_sheet_music integration once the rendering API is wired up.
class SimpleSheetMusicAdapter extends NotationRenderer {
  const SimpleSheetMusicAdapter({
    super.key,
    required super.data,
    super.height,
  });

  @override
  Widget build(BuildContext context) {
    final noteNames = data.pitches
        .map((pc) => NoteName.toSharp(pc))
        .join(', ');

    final label = data.label != null ? '${data.label}: ' : '';

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note,
              size: 28,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 4),
            Text(
              '$label$noteNames',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (data.showKeySignature && data.keySigSharps != null)
              Text(
                _keySigDescription(data.keySigSharps!),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  String _keySigDescription(int sharps) {
    if (sharps == 0) return 'No sharps or flats';
    if (sharps > 0) return '$sharps sharp${sharps == 1 ? '' : 's'}';
    final flats = sharps.abs();
    return '$flats flat${flats == 1 ? '' : 's'}';
  }
}
