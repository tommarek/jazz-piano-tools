import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../content/providers/content_providers.dart';
import '../../../domain/models/exercise.dart';
import '../../drill/generators/generator_registry.dart';
import '../providers/exercise_counts_provider.dart';

class PracticeHubScreen extends ConsumerWidget {
  const PracticeHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercisesAsync = ref.watch(allExercisesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: exercisesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('Failed to load exercises',
              style: theme.textTheme.bodyLarge),
        ),
        data: (exercises) => _buildExerciseList(context, ref, exercises),
      ),
    );
  }

  Widget _buildExerciseList(
      BuildContext context, WidgetRef ref, List<Exercise> exercises) {
    final theme = Theme.of(context);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: exercises.length,
      itemBuilder: (context, index) {
        final exercise = exercises[index];
        final generator = resolveGenerator(exercise.generatorId);
        final totalItems = generator.allItemIds(exercise).length;
        final countsAsync = ref.watch(exerciseCountsProvider(exercise.id));
        final counts = countsAsync.valueOrNull;

        return Card(
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => context.push('/session-builder/${exercise.id}'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(exercise.title,
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: [
                            _badge(
                              '$totalItems cards',
                              theme.colorScheme.surfaceContainerHighest,
                              theme.colorScheme.onSurfaceVariant,
                              theme,
                            ),
                            if (counts != null && counts.reviewCount > 0)
                              _badge(
                                '${counts.reviewCount} due',
                                theme.colorScheme.tertiaryContainer,
                                theme.colorScheme.onTertiaryContainer,
                                theme,
                              ),
                            if (counts != null && counts.newCount > 0)
                              _badge(
                                '${counts.newCount} new',
                                theme.colorScheme.primaryContainer,
                                theme.colorScheme.onPrimaryContainer,
                                theme,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        );
      },
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
