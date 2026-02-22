import 'package:flutter/material.dart';

/// SRS rating button row (Again / Hard / Good / Easy).
class RatingButtons extends StatelessWidget {
  final ValueChanged<int> onRate;
  final String Function(int rating)? sublabelBuilder;
  final String? headerText;

  const RatingButtons({
    required this.onRate,
    this.sublabelBuilder,
    this.headerText,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (headerText != null) ...[
          Text(headerText!, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            _RatingButton(
              label: 'Again',
              sublabel: sublabelBuilder?.call(0) ?? '',
              color: theme.colorScheme.error,
              onPressed: () => onRate(0),
            ),
            const SizedBox(width: 8),
            _RatingButton(
              label: 'Hard',
              sublabel: sublabelBuilder?.call(1) ?? '',
              color: Colors.orange,
              onPressed: () => onRate(1),
            ),
            const SizedBox(width: 8),
            _RatingButton(
              label: 'Good',
              sublabel: sublabelBuilder?.call(2) ?? '',
              color: Colors.green,
              onPressed: () => onRate(2),
            ),
            const SizedBox(width: 8),
            _RatingButton(
              label: 'Easy',
              sublabel: sublabelBuilder?.call(3) ?? '',
              color: theme.colorScheme.primary,
              onPressed: () => onRate(3),
            ),
          ],
        ),
      ],
    );
  }
}

class _RatingButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback onPressed;

  const _RatingButton({
    required this.label,
    this.sublabel = '',
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (sublabel.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                sublabel,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
