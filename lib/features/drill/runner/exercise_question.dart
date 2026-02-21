import '../../../core/widgets/notation/notation_renderer.dart';

class ExerciseQuestion {
  final String promptText;
  final NotationData? notationData;
  final dynamic expectedAnswer;
  final Map<String, dynamic> acceptanceRules;
  final Map<String, dynamic> metadata;
  final List<String>? multipleChoiceOptions;

  const ExerciseQuestion({
    required this.promptText,
    this.notationData,
    required this.expectedAnswer,
    this.acceptanceRules = const {},
    this.metadata = const {},
    this.multipleChoiceOptions,
  });
}
