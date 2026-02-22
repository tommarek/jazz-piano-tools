import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../progression_service.dart';
import '../providers/progression_provider.dart';

class ProgressionScreen extends ConsumerWidget {
  final String topic;

  const ProgressionScreen({required this.topic, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiersAsync = ref.watch(tiersByTopicProvider(topic));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${_capitalize(topic)} Progression'),
      ),
      body: tiersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (tiers) {
          if (tiers.isEmpty) {
            return Center(
              child: Text(
                'No tiers available yet',
                style: theme.textTheme.bodyLarge,
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tiers.length,
            itemBuilder: (context, index) {
              return _TierCard(tierWithProgress: tiers[index]);
            },
          );
        },
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _TierCard extends StatelessWidget {
  final TierWithProgress tierWithProgress;

  const _TierCard({required this.tierWithProgress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tier = tierWithProgress.tier;
    final isUnlocked = tierWithProgress.isUnlocked;
    final mastery = tierWithProgress.mastery;
    final attempts = tierWithProgress.attempts;
    final level = ProgressionService.masteryLevel(mastery, attempts);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: isUnlocked ? 1.0 : 0.5,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isUnlocked
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: isUnlocked
                          ? Text(
                              '${tier.tierNumber}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : Icon(
                              Icons.lock,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tier.title, style: theme.textTheme.titleMedium),
                        Text(
                          tier.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isUnlocked && attempts > 0)
                    Chip(
                      label: Text(level),
                      labelStyle: theme.textTheme.labelSmall,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
              if (isUnlocked && attempts > 0) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: mastery,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
                const SizedBox(height: 4),
                Text(
                  '${(mastery * 100).round()}% mastery  |  $attempts attempts',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (!isUnlocked) ...[
                const SizedBox(height: 8),
                Text(
                  'Complete the previous tier to unlock',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
