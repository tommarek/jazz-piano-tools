import '../../../core/audio/audio_service.dart';
import '../../../core/audio/pitched_note.dart';
import '../../../core/widgets/notation/notation_renderer.dart';

class ExerciseQuestion {
  final String promptText;
  final NotationData? notationData;
  final dynamic expectedAnswer;

  /// Human-readable answer text for display (e.g. "Bb" instead of a PitchClass set).
  final String? answerText;
  final Map<String, dynamic> acceptanceRules;
  final Map<String, dynamic> metadata;
  final List<String>? multipleChoiceOptions;
  final AudioQuestionData? audioData;

  const ExerciseQuestion({
    required this.promptText,
    this.notationData,
    required this.expectedAnswer,
    this.answerText,
    this.acceptanceRules = const {},
    this.metadata = const {},
    this.multipleChoiceOptions,
    this.audioData,
  });
}

/// Audio data attached to a question for ear training exercises.
class AudioQuestionData {
  final List<PitchedNote> notes;
  final PlaybackMode playbackMode;
  final bool allowReplay;

  const AudioQuestionData({
    required this.notes,
    this.playbackMode = PlaybackMode.melodicAscending,
    this.allowReplay = true,
  });
}
