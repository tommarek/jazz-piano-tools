import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../srs/providers/srs_provider.dart';
import '../../streak/providers/streak_provider.dart';
import '../providers/today_session_provider.dart';

class EndSummaryScreen extends ConsumerWidget {
  final int cardsReviewed;
  final int correctCount;
  final VoidCallback? onDone;

  const EndSummaryScreen({
    required this.cardsReviewed,
    required this.correctCount,
    this.onDone,
    super.key,
  });

  int get score =>
      cardsReviewed > 0 ? ((correctCount / cardsReviewed) * 100).round() : 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Complete'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.celebration,
                size: 80,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(height: 24),
              Text(
                'Well Done!',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),

              // Stats
              _StatRow(
                icon: Icons.flip,
                label: 'Cards Reviewed',
                value: '$cardsReviewed',
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              _StatRow(
                icon: Icons.check_circle,
                label: 'Correct',
                value: '$correctCount / $cardsReviewed',
                color: Colors.green,
              ),
              const SizedBox(height: 16),
              _StatRow(
                icon: Icons.stars,
                label: 'Score',
                value: '$score%',
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(height: 48),

              // Done button
              FilledButton(
                onPressed: () {
                  if (onDone != null) {
                    onDone!();
                    return;
                  }
                  ref.invalidate(todaySessionProvider);
                  ref.invalidate(todayDashboardCountsProvider);
                  ref.invalidate(todayCategoryDashboardCountsProvider(TodayReviewCategory.learning));
                  ref.invalidate(todayCategoryDashboardCountsProvider(TodayReviewCategory.ear));
                  ref.invalidate(todayStreakProvider);
                  ref.invalidate(dueCardCountProvider);
                  context.go('/today');
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(label, style: theme.textTheme.bodyLarge),
        ),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
