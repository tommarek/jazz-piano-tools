import '../../domain/enums/answer_type.dart';

enum AnswerInputMode { keyboard, multipleChoice, selfReveal }

extension AnswerInputModeX on AnswerInputMode {
  /// From the settings string stored in the database ('keyboard', 'multipleChoice', 'none').
  static AnswerInputMode fromSettingsString(String value) {
    switch (value) {
      case 'keyboard':
        return AnswerInputMode.keyboard;
      case 'multipleChoice':
        return AnswerInputMode.multipleChoice;
      default:
        return AnswerInputMode.selfReveal;
    }
  }

  /// From a card's [AnswerType] (used by SRS deck review screens).
  static AnswerInputMode fromAnswerType(AnswerType type) {
    switch (type) {
      case AnswerType.pitch:
        return AnswerInputMode.keyboard;
      case AnswerType.multipleChoice:
        return AnswerInputMode.multipleChoice;
      case AnswerType.text:
      case AnswerType.chordName:
      case AnswerType.intervalName:
        return AnswerInputMode.selfReveal;
    }
  }
}
