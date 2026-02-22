import 'package:flutter/material.dart';

/// Shows a modal bottom sheet for configuring a review/practice session.
///
/// Returns the chosen question count, or null if dismissed.
Future<int?> showSessionConfigSheet({
  required BuildContext context,
  required int availableCount,
  required String subtitle,
}) {
  return showModalBottomSheet<int>(
    context: context,
    builder: (context) => _SessionConfigSheet(
      availableCount: availableCount,
      subtitle: subtitle,
    ),
  );
}

class _SessionConfigSheet extends StatefulWidget {
  final int availableCount;
  final String subtitle;

  const _SessionConfigSheet({
    required this.availableCount,
    required this.subtitle,
  });

  @override
  State<_SessionConfigSheet> createState() => _SessionConfigSheetState();
}

class _SessionConfigSheetState extends State<_SessionConfigSheet> {
  int? _selectedCount;

  List<int> get _presets {
    final presets = <int>[];
    for (final n in [5, 10, 15, 20]) {
      if (n <= widget.availableCount) presets.add(n);
    }
    return presets;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Start Session',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'How many cards?',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ..._presets.map((n) => ChoiceChip(
                      label: Text('$n'),
                      selected: _selectedCount == n,
                      onSelected: (_) => setState(() => _selectedCount = n),
                    )),
                ChoiceChip(
                  label: Text('All (${widget.availableCount})'),
                  selected: _selectedCount == widget.availableCount,
                  onSelected: (_) =>
                      setState(() => _selectedCount = widget.availableCount),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _selectedCount != null
                  ? () => Navigator.of(context).pop(_selectedCount)
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Start'),
            ),
          ],
        ),
      ),
    );
  }
}
