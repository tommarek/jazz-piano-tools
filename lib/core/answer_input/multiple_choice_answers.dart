import 'package:flutter/material.dart';

class MultipleChoiceAnswers extends StatelessWidget {
  final List<String> options;
  final String correctAnswer;
  final String? selectedAnswer;
  final bool showResult;
  final bool disabled;
  final ValueChanged<String>? onSelected;

  const MultipleChoiceAnswers({
    required this.options,
    required this.correctAnswer,
    this.selectedAnswer,
    this.showResult = false,
    this.disabled = false,
    this.onSelected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: options.map((option) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _OptionButton(
            label: option,
            isCorrect: option == correctAnswer,
            isSelected: option == selectedAnswer,
            showResult: showResult,
            onTap: disabled ? null : () => onSelected?.call(option),
          ),
        );
      }).toList(),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final String label;
  final bool isCorrect;
  final bool isSelected;
  final bool showResult;
  final VoidCallback? onTap;

  const _OptionButton({
    required this.label,
    required this.isCorrect,
    required this.isSelected,
    required this.showResult,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color? backgroundColor;
    Color? foregroundColor;
    Color? borderColor;

    if (showResult) {
      if (isSelected && isCorrect) {
        backgroundColor = Colors.green.withValues(alpha: 0.12);
        foregroundColor = Colors.green;
        borderColor = Colors.green;
      } else if (isSelected && !isCorrect) {
        backgroundColor = Colors.red.withValues(alpha: 0.12);
        foregroundColor = Colors.red;
        borderColor = Colors.red;
      } else if (isCorrect) {
        // Reveal correct answer
        backgroundColor = Colors.green.withValues(alpha: 0.06);
        borderColor = Colors.green.withValues(alpha: 0.5);
        foregroundColor = Colors.green;
      }
    }

    return Material(
      color: backgroundColor ?? Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: borderColor ??
              theme.colorScheme.outlineVariant,
          width: isSelected && showResult ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: foregroundColor,
                    fontWeight:
                        isSelected || (showResult && isCorrect)
                            ? FontWeight.bold
                            : null,
                  ),
                ),
              ),
              if (showResult && isSelected && isCorrect)
                const Icon(Icons.check_circle, color: Colors.green),
              if (showResult && isSelected && !isCorrect)
                const Icon(Icons.cancel, color: Colors.red),
              if (showResult && !isSelected && isCorrect)
                Icon(Icons.check_circle_outline,
                    color: Colors.green.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}
