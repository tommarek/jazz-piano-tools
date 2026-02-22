import 'package:flutter/material.dart';

class SessionAppBarTitle extends StatelessWidget {
  final String title;
  final List<String> subtitleParts;

  const SessionAppBarTitle({
    required this.title,
    required this.subtitleParts,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = subtitleParts.where((p) => p.isNotEmpty).join(' | ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
