import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/concepts_provider.dart';
import '../../../content/providers/content_providers.dart';
import '../../../domain/models/concept.dart';
import '../../../domain/models/exercise.dart';
import '../../drill/screens/drill_screen.dart';
import '../../drill/screens/learn_screen.dart';
import '../../drill/screens/practice_screen.dart';
import '../../drill/widgets/practice_launch_sheet.dart';
import '../../library/providers/library_provider.dart';

class ConceptDetailScreen extends ConsumerStatefulWidget {
  final String conceptId;

  const ConceptDetailScreen({required this.conceptId, super.key});

  @override
  ConsumerState<ConceptDetailScreen> createState() =>
      _ConceptDetailScreenState();
}

class _ConceptDetailScreenState extends ConsumerState<ConceptDetailScreen> {
  bool _theoryExpanded = false;

  @override
  Widget build(BuildContext context) {
    final conceptAsync = ref.watch(conceptByIdProvider(widget.conceptId));

    return conceptAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $error')),
      ),
      data: (concept) => Scaffold(
        appBar: AppBar(
          title: Text(concept.title),
        ),
        body: _buildBody(context, concept),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Concept concept) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Level badge and tags
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'Level ${concept.level}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (concept.tags.isNotEmpty)
              ...concept.tags.take(3).map(
                    (tag) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Chip(
                        label: Text(tag),
                        labelStyle: theme.textTheme.labelSmall,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
          ],
        ),
        const SizedBox(height: 16),

        // Summary
        if (concept.summary.isNotEmpty) ...[
          Text(
            concept.summary,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Theory section — collapsible
        if (concept.bodyMarkdown.isNotEmpty) ...[
          InkWell(
            onTap: () =>
                setState(() => _theoryExpanded = !_theoryExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _theoryExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Theory',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_theoryExpanded) ...[
            const SizedBox(height: 8),
            MarkdownBody(
              data: concept.bodyMarkdown,
              selectable: true,
              styleSheet:
                  MarkdownStyleSheet.fromTheme(theme).copyWith(
                h1: theme.textTheme.headlineMedium,
                h2: theme.textTheme.headlineSmall,
                h3: theme.textTheme.titleLarge,
                p: theme.textTheme.bodyLarge,
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],

        // Practice section — inline groups with direct Start Practice
        if (concept.relatedExerciseIds.isNotEmpty) ...[
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Practice',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _PracticeSection(
            exerciseIds: concept.relatedExerciseIds,
          ),
        ],
      ],
    );
  }
}

class _PracticeSection extends ConsumerWidget {
  final List<String> exerciseIds;

  const _PracticeSection({required this.exerciseIds});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercisesAsync = ref.watch(allExercisesProvider);

    return exercisesAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, _) => Text('Error: $error'),
      data: (allExercises) {
        final matched = exerciseIds
            .map((id) => allExercises.where((e) => e.id == id).firstOrNull)
            .whereType<Exercise>()
            .toList();

        final showHeaders = matched.length > 1;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < matched.length; i++) ...[
              if (i > 0) const SizedBox(height: 24),
              _ExerciseGroupSection(
                exercise: matched[i],
                showHeader: showHeaders,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ExerciseGroupSection extends ConsumerStatefulWidget {
  final Exercise exercise;
  final bool showHeader;

  const _ExerciseGroupSection({
    required this.exercise,
    required this.showHeader,
  });

  @override
  ConsumerState<_ExerciseGroupSection> createState() =>
      _ExerciseGroupSectionState();
}

class _ExerciseGroupSectionState
    extends ConsumerState<_ExerciseGroupSection> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exercise = widget.exercise;
    final countsAsync = ref.watch(exerciseCountsProvider(exercise.id));
    final groupCountsAsync =
        ref.watch(exerciseGroupCountsProvider(exercise.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader) ...[
          Text(
            exercise.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Summary row with Practice button → opens launch sheet
        countsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (counts) => _SummaryRow(
            counts: counts,
            onStart: () => _openLaunchSheet(context),
          ),
        ),

        const SizedBox(height: 8),

        // Group list (read-only)
        groupCountsAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => Text('Error: $error'),
          data: (groups) => Column(
            children: groups
                .map((group) => _GroupRow(group: group))
                .toList(),
          ),
        ),
      ],
    );
  }

  void _openLaunchSheet(BuildContext context) async {
    final exercise = widget.exercise;
    final result = await showPracticeLaunchSheet(
      context: context,
      exerciseId: exercise.id,
    );
    if (result == null || !context.mounted) return;

    final Widget screen;
    switch (result.mode) {
      case PracticeMode.review:
        screen = PracticeScreen(
          exerciseId: exercise.id,
          selectedGroups: result.selectedGroups,
          newCardCount: result.newCardCount,
        );
      case PracticeMode.practiceLearned:
        screen = PracticeScreen(
          exerciseId: exercise.id,
          selectedGroups: result.selectedGroups,
          learnedOnly: true,
        );
      case PracticeMode.learn:
        screen = ExerciseLearnScreen(
          exerciseId: exercise.id,
          selectedGroups: result.selectedGroups,
          questionCount: result.questionCount,
        );
      case PracticeMode.speedTest:
        screen = DrillScreen(
          exerciseId: exercise.id,
          selectedGroups: result.selectedGroups,
          questionCount: result.questionCount,
        );
    }

    // Push over root navigator so bottom nav is hidden
    await Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    ref.invalidate(exerciseCountsProvider(exercise.id));
    ref.invalidate(exerciseGroupCountsProvider(exercise.id));
  }
}

class _SummaryRow extends StatelessWidget {
  final ExerciseCounts counts;
  final VoidCallback onStart;

  const _SummaryRow({required this.counts, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDue = counts.reviewCount > 0 || counts.newCount > 0;

    final parts = <String>[];
    if (counts.reviewCount > 0) {
      parts.add('${counts.reviewCount} to review');
    }
    if (counts.newCount > 0) {
      parts.add('${counts.newCount} new');
    }

    return Row(
      children: [
        Expanded(
          child: hasDue
              ? Wrap(
                  spacing: 6,
                  children: [
                    if (counts.reviewCount > 0)
                      _badge(
                        '${counts.reviewCount} to review',
                        theme.colorScheme.tertiaryContainer,
                        theme.colorScheme.onTertiaryContainer,
                        theme,
                      ),
                    if (counts.newCount > 0)
                      _badge(
                        '${counts.newCount} new',
                        theme.colorScheme.primaryContainer,
                        theme.colorScheme.onPrimaryContainer,
                        theme,
                      ),
                  ],
                )
              : Text(
                  counts.availableNew > 0
                      ? 'All caught up \u00b7 ${counts.availableNew} to explore'
                      : 'All caught up',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: onStart,
          child: const Text('Practice'),
        ),
      ],
    );
  }

  Widget _badge(String label, Color bg, Color fg, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  final GroupCounts group;

  const _GroupRow({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              group.groupName,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          Text(
            '${group.totalItems} items',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          if (group.dueCount > 0)
            _badge(
              '${group.dueCount} due',
              theme.colorScheme.tertiaryContainer,
              theme.colorScheme.onTertiaryContainer,
              theme,
            ),
          if (group.dueCount > 0 && group.newCount > 0)
            const SizedBox(width: 4),
          if (group.newCount > 0)
            _badge(
              '${group.newCount} new',
              theme.colorScheme.primaryContainer,
              theme.colorScheme.onPrimaryContainer,
              theme,
            ),
          if (group.dueCount == 0 &&
              group.newCount == 0 &&
              group.learnedCount > 0)
            _badge(
              '${group.learnedCount} learned',
              theme.colorScheme.surfaceContainerHighest,
              theme.colorScheme.onSurfaceVariant,
              theme,
            ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color bg, Color fg, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
