import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'audio_service.dart';
import 'midi_audio_service.dart';

part 'audio_provider.g.dart';

@Riverpod(keepAlive: true)
AudioService audioService(AudioServiceRef ref) {
  final service = MidiAudioService();
  service.init();
  ref.onDispose(() => service.dispose());
  return service;
}
