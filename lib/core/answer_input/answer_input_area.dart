import 'package:flutter/material.dart';

import '../widgets/piano_input/flutter_piano_pro_adapter.dart';
import 'answer_feedback_banner.dart';
import 'answer_input_controller.dart';
import 'answer_input_mode.dart';
import 'multiple_choice_answers.dart';

/// Composite body widget that renders the correct answer input UI
/// based on the controller's mode and state.
class AnswerInputArea extends StatelessWidget {
  final AnswerInputController controller;

  /// Optional widget shown after answer (e.g. notation).
  final Widget? feedbackExtra;

  /// Optional text for next review time (shown in feedback banner).
  final String? nextReviewText;

  const AnswerInputArea({
    required this.controller,
    this.feedbackExtra,
    this.nextReviewText,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        switch (controller.mode) {
          case AnswerInputMode.multipleChoice:
            return _buildMcq(context);
          case AnswerInputMode.keyboard:
            return _buildKeyboard(context);
          case AnswerInputMode.selfReveal:
            return _buildSelfReveal(context);
        }
      },
    );
  }

  Widget _buildMcq(BuildContext context) {
    final options = controller.multipleChoiceOptions;
    if (options == null) return const SizedBox.shrink();

    if (controller.phase == AnswerPhase.input) {
      return MultipleChoiceAnswers(
        options: options,
        correctAnswer: controller.expectedAnswer.toString(),
        showResult: false,
        disabled: false,
        onSelected: controller.selectMcqAnswer,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MultipleChoiceAnswers(
          options: options,
          correctAnswer: controller.expectedAnswer.toString(),
          selectedAnswer: controller.selectedMcqAnswer,
          showResult: true,
          disabled: true,
        ),
        if (feedbackExtra != null) ...[
          const SizedBox(height: 16),
          feedbackExtra!,
        ],
        const SizedBox(height: 16),
        AnswerFeedbackBanner(
          isCorrect: controller.result!,
          answerText: controller.displayAnswer,
          nextReviewText: nextReviewText,
        ),
      ],
    );
  }

  Widget _buildKeyboard(BuildContext context) {
    final theme = Theme.of(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final octaveCount = isLandscape ? 2 : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: FlutterPianoProAdapter(
            octaveCount: octaveCount,
            startOctave: 4,
            highlightedNotes: controller.keyboardSubmitted
                ? controller.expectedPitchClasses
                : const {},
            onNotesChanged: controller.keyboardSubmitted
                ? null
                : controller.updateKeyboardNotes,
          ),
        ),
        if (controller.isMultiNote &&
            controller.phase == AnswerPhase.input) ...[
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed:
                controller.canSubmitKeyboard ? controller.submitKeyboard : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            child: const Text('Submit'),
          ),
        ],
        if (controller.keyboardSubmitted) ...[
          const SizedBox(height: 16),
          if (feedbackExtra != null) ...[
            feedbackExtra!,
            const SizedBox(height: 16),
          ],
          _buildAnswerCard(theme),
          const SizedBox(height: 16),
          AnswerFeedbackBanner(
            isCorrect: controller.result!,
            answerText: controller.displayAnswer,
            nextReviewText: nextReviewText,
          ),
        ],
      ],
    );
  }

  Widget _buildSelfReveal(BuildContext context) {
    final theme = Theme.of(context);
    if (!controller.answerRevealed) return const SizedBox.shrink();

    return _buildAnswerCard(theme);
  }

  Widget _buildAnswerCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              'Answer',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              controller.displayAnswer,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
