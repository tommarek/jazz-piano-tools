import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/concepts_provider.dart';
import '../../../content/providers/content_providers.dart';
import '../../../domain/models/concept.dart';
import '../../drill/screens/drill_screen.dart';
import '../../drill/screens/practice_screen.dart';

class ConceptDetailScreen extends ConsumerWidget {
  final String conceptId;

  const ConceptDetailScreen({required this.conceptId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conceptAsync = ref.watch(conceptByIdProvider(conceptId));

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
        body: _buildBody(context, ref, concept),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, Concept concept) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Level badge and title
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
          const Divider(),
          const SizedBox(height: 16),
        ],

        // Markdown body
        MarkdownBody(
          data: concept.bodyMarkdown,
          selectable: true,
          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
            h1: theme.textTheme.headlineMedium,
            h2: theme.textTheme.headlineSmall,
            h3: theme.textTheme.titleLarge,
            p: theme.textTheme.bodyLarge,
          ),
        ),
        const SizedBox(height: 24),

        // Related exercises
        if (concept.relatedExerciseIds.isNotEmpty) ...[
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Try It Now',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...concept.relatedExerciseIds.map(
            (exerciseId) => _ExerciseButton(
              exerciseId: exerciseId,
              ref: ref,
            ),
          ),
        ],
      ],
    );
  }
}

class _ExerciseButton extends StatelessWidget {
  final String exerciseId;
  final WidgetRef ref;

  const _ExerciseButton({
    required this.exerciseId,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final exercisesAsync = ref.watch(allExercisesProvider);

    return exercisesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (exercises) {
        final exercise = exercises.where((e) => e.id == exerciseId).firstOrNull;
        if (exercise == null) return const SizedBox.shrink();

        final isDrill = exercise.mode.name == 'drill';

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => isDrill
                      ? DrillScreen(exerciseId: exerciseId)
                      : PracticeScreen(exerciseId: exerciseId),
                ),
              );
            },
            icon: Icon(isDrill ? Icons.speed : Icons.piano),
            label: Text(exercise.title),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              alignment: Alignment.centerLeft,
            ),
          ),
        );
      },
    );
  }
}
