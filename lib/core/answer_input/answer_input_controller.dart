import 'package:flutter/foundation.dart';

import '../answer_checker/pitch_answer_checker.dart';
import '../music/pitch_class.dart';
import 'answer_input_mode.dart';
import 'pitch_class_parser.dart';

enum AnswerPhase { input, feedback }

class AnswerInputController extends ChangeNotifier {
  final AnswerInputMode mode;
  final dynamic expectedAnswer;
  final String? answerText;
  final List<String>? multipleChoiceOptions;
  final void Function(bool isCorrect) onResult;

  AnswerInputController({
    required this.mode,
    required this.expectedAnswer,
    this.answerText,
    this.multipleChoiceOptions,
    required this.onResult,
  });

  // --- State ---
  AnswerPhase _phase = AnswerPhase.input;
  Set<PitchClass> _keyboardNotes = const {};
  bool _keyboardSubmitted = false;
  String? _selectedMcqAnswer;
  bool? _result; // null = not answered, true/false = correct/incorrect
  bool _answerRevealed = false;

  // --- Getters ---
  AnswerPhase get phase => _phase;
  Set<PitchClass> get keyboardNotes => _keyboardNotes;
  bool get keyboardSubmitted => _keyboardSubmitted;
  String? get selectedMcqAnswer => _selectedMcqAnswer;
  bool? get result => _result;
  bool get answerRevealed => _answerRevealed;

  Set<PitchClass> get expectedPitchClasses =>
      PitchClassParser.extract(expectedAnswer);

  bool get isMultiNote => expectedPitchClasses.length > 1;

  bool get canSubmitKeyboard =>
      _keyboardNotes.isNotEmpty && !_keyboardSubmitted;

  String get displayAnswer {
    if (answerText != null) return answerText!;
    if (expectedAnswer == null) return '';
    if (expectedAnswer is Set) {
      return (expectedAnswer as Set).map((e) => e.toString()).join(', ');
    }
    return expectedAnswer.toString();
  }

  // --- Actions ---

  void selectMcqAnswer(String option) {
    if (_phase == AnswerPhase.feedback) return;

    final correct = option == expectedAnswer.toString();
    _selectedMcqAnswer = option;
    _result = correct;
    _phase = AnswerPhase.feedback;
    notifyListeners();

    onResult(correct);
  }

  void updateKeyboardNotes(Set<PitchClass> notes) {
    if (_keyboardSubmitted) return;
    _keyboardNotes = notes;
    notifyListeners();

    // Auto-submit for single-note answers
    if (!isMultiNote && notes.length == 1) {
      submitKeyboard();
    }
  }

  void submitKeyboard() {
    if (_keyboardSubmitted) return;

    final expected = expectedPitchClasses;
    final checker = PitchSetAnswerChecker();
    final checkResult = checker.check(expected, _keyboardNotes);

    _keyboardSubmitted = true;
    _result = checkResult.isCorrect;
    _phase = AnswerPhase.feedback;
    notifyListeners();

    onResult(checkResult.isCorrect);
  }

  void revealAnswer() {
    _answerRevealed = true;
    _phase = AnswerPhase.feedback;
    notifyListeners();
  }
}
