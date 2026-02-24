import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../streak/providers/streak_provider.dart';
import '../providers/today_session_provider.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(todaySessionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
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
        const SizedBox(height: 12),
        Consumer(
          builder: (context, ref, _) {
            final streakAsync = ref.watch(todayStreakProvider);
            final streak = streakAsync.asData?.value ?? const TodayStreakState();
            return _StreakChip(streak: streak);
          },
        ),
        const SizedBox(height: 24),

        _CategoryReviewCard(
          title: 'Learning to Review',
          category: TodayReviewCategory.learning,
          icon: Icons.school,
          iconColor: theme.colorScheme.primary,
        ),
        const SizedBox(height: 12),
        _CategoryReviewCard(
          title: 'Ear Training to Review',
          category: TodayReviewCategory.ear,
          icon: Icons.hearing,
          iconColor: theme.colorScheme.tertiary,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _StreakChip extends StatelessWidget {
  final TodayStreakState streak;

  const _StreakChip({required this.streak});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = streak.todayComplete
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final fg = streak.todayComplete
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onSurface;
    final sub = streak.todayComplete ? 'done today' : 'finish Learning or Ear today';

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            _SevenFlamesStrip(streak: streak),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${streak.currentStreakDays} day streak',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (streak.bestStreakDays > 0) ...[
              const SizedBox(width: 8),
              Text(
                'Best ${streak.bestStreakDays}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SevenFlamesStrip extends StatelessWidget {
  final TodayStreakState streak;

  const _SevenFlamesStrip({required this.streak});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = streak.lastSevenDays;
    if (days.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final day in days)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: _FlameDayDot(
              isActive: day.isActive,
              isToday: day.isToday,
              todayProgress: day.isToday ? streak.todayProgress : 0,
              todayComplete: streak.todayComplete,
              colorScheme: theme.colorScheme,
            ),
          ),
      ],
    );
  }
}

class _FlameDayDot extends StatelessWidget {
  final bool isActive;
  final bool isToday;
  final double todayProgress;
  final bool todayComplete;
  final ColorScheme colorScheme;

  const _FlameDayDot({
    required this.isActive,
    required this.isToday,
    required this.todayProgress,
    required this.todayComplete,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isToday ? Colors.orange.shade700 : Colors.orange.shade500;
    final baseColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.45);
    final colorProgress = isToday ? (todayComplete ? 1.0 : 0.0) : (isActive ? 1.0 : 0.0);

    return SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isToday)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                value: todayComplete ? 1 : todayProgress,
                strokeWidth: 2,
                backgroundColor: colorScheme.outlineVariant.withValues(alpha: 0.35),
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.orange.shade400,
                ),
              ),
            ),
          Icon(
            Icons.local_fire_department,
            size: 14,
            color: baseColor,
          ),
          Icon(
            Icons.local_fire_department,
            size: 14,
            color: activeColor.withValues(alpha: colorProgress),
          ),
        ],
      ),
    );
  }
}

class _CategoryReviewCard extends ConsumerWidget {
  final String title;
  final TodayReviewCategory category;
  final IconData icon;
  final Color iconColor;

  const _CategoryReviewCard({
    required this.title,
    required this.category,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final countsAsync = ref.watch(todayCategoryDashboardCountsProvider(category));
    final counts = countsAsync.asData?.value;
    final due = counts?.dueCardCount ?? 0;
    final learning = counts?.learningDueCount ?? 0;
    final review = counts?.reviewDueCount ?? 0;
    final estMin = counts?.estimatedMinutes ?? 0;

    return _SessionCard(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: due > 0
          ? '$due due (L$learning · R$review) · ~$estMin min'
          : 'All caught up',
      trailing: due > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '$due',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : Icon(Icons.check_circle, color: Colors.green.shade600),
      onTap: due > 0 ? () => context.push('/review', extra: category.name) : null,
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
