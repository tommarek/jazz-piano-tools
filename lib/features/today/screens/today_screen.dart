import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/today_session_provider.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(todaySessionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Today')),
      body: sessionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text('Something went wrong', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => ref.invalidate(todaySessionProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (session) => _buildSessionContent(context, session),
      ),
    );
  }

  Widget _buildSessionContent(BuildContext context, TodaySessionState session) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header
        Text(
          "Today's Session",
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Estimated time: ${session.sessionEstimateMinutes} min',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        // Due reviews card
        _SessionCard(
          icon: Icons.flip,
          iconColor: theme.colorScheme.primary,
          title: 'Cards to Review',
          subtitle: session.dueCardCount > 0
              ? '${session.dueCardCount} cards due'
              : 'All caught up!',
          trailing: session.dueCardCount > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${session.dueCardCount}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : Icon(Icons.check_circle, color: Colors.green.shade600),
          onTap: session.dueCardCount > 0
              ? () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const _ReviewSessionPlaceholder(),
                    ),
                  );
                }
              : null,
        ),
        const SizedBox(height: 12),

        // Drill suggestion card
        _SessionCard(
          icon: Icons.speed,
          iconColor: theme.colorScheme.secondary,
          title: 'Suggested Drills',
          subtitle: session.suggestedDrillIds.isNotEmpty
              ? '${session.suggestedDrillIds.length} drills available'
              : 'No drills suggested',
          trailing: const Icon(Icons.chevron_right),
          onTap: session.suggestedDrillIds.isNotEmpty ? () {} : null,
        ),
        const SizedBox(height: 12),

        // Practice suggestion card
        _SessionCard(
          icon: Icons.piano,
          iconColor: Colors.teal,
          title: 'Suggested Practice',
          subtitle: session.suggestedPracticeIds.isNotEmpty
              ? '${session.suggestedPracticeIds.length} exercises available'
              : 'No practice suggested',
          trailing: const Icon(Icons.chevron_right),
          onTap: session.suggestedPracticeIds.isNotEmpty ? () {} : null,
        ),
        const SizedBox(height: 32),

        // Start session button
        FilledButton(
          onPressed: session.dueCardCount > 0
              ? () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const _ReviewSessionPlaceholder(),
                    ),
                  );
                }
              : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
          child: const Text('Start Session'),
        ),
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SessionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Temporary placeholder until ReviewSessionScreen is wired into routing.
class _ReviewSessionPlaceholder extends StatelessWidget {
  const _ReviewSessionPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review Session')),
      body: const Center(child: Text('Review session coming soon')),
    );
  }
}
