import 'package:flutter/material.dart';

/// Correct/incorrect feedback card used across all answer input screens.
class AnswerFeedbackBanner extends StatelessWidget {
  final bool isCorrect;
  final String answerText;
  final String? nextReviewText;

  const AnswerFeedbackBanner({
    required this.isCorrect,
    required this.answerText,
    this.nextReviewText,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isCorrect
          ? Colors.green.withValues(alpha: 0.12)
          : Colors.red.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isCorrect ? Icons.check_circle : Icons.cancel,
              color: isCorrect ? Colors.green : Colors.red,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCorrect ? 'Correct!' : 'Incorrect',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isCorrect ? Colors.green : Colors.red,
                      fontSize: 16,
                    ),
                  ),
                  if (!isCorrect) ...[
                    const SizedBox(height: 4),
                    Text('Answer: $answerText'),
                  ],
                  if (nextReviewText != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Next review: $nextReviewText',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
