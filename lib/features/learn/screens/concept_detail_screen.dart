import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../providers/concepts_provider.dart';
import '../../../content/providers/content_providers.dart';
import '../../../domain/models/concept.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/enums/input_type.dart';
import '../providers/deck_review_provider.dart';
import '../widgets/deck_session_sheet.dart';
import '../../drill/screens/session_builder_screen.dart';
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

        // Theory section — compact summary + expand
        if (concept.bodyMarkdown.isNotEmpty ||
            concept.summary.isNotEmpty ||
            concept.examples.isNotEmpty) ...[
          _buildTheoryCard(theme, concept),
          if (_theoryExpanded && concept.bodyMarkdown.isNotEmpty) ...[
            const SizedBox(height: 12),
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

        if (concept.id == 'intervals-basic' &&
            concept.relatedCardDeckIds.isNotEmpty) ...[
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Decks',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _DecksSection(deckIds: concept.relatedCardDeckIds),
        ] else if (concept.relatedExerciseIds.isNotEmpty) ...[
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Exercises',
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

class _DecksSection extends ConsumerWidget {
  final List<String> deckIds;

  const _DecksSection({required this.deckIds});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decksAsync = ref.watch(deckTreeStatsProvider(deckIds));
    final theme = Theme.of(context);

    return decksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('Error: $error'),
      data: (nodes) {
        final theory = nodes.where((n) => _hasTag(n, 'modality:theory')).toList();
        final ear = nodes.where((n) => _hasTag(n, 'modality:ear')).toList();
        final piano = nodes.where((n) => _hasTag(n, 'modality:piano')).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DeckSection(
              title: 'Theory',
              nodes: theory,
              emptyLabel: 'No theory decks yet.',
            ),
            const SizedBox(height: 16),
            _DeckSection(
              title: 'Ear Training',
              nodes: ear,
              emptyLabel: 'No ear training decks yet.',
            ),
          ],
        );
      },
    );
  }

  bool _hasTag(DeckTreeNode node, String tag) {
    return node.deck.tags.contains(tag);
  }
}

class _DeckSection extends ConsumerWidget {
  final String title;
  final List<DeckTreeNode> nodes;
  final String emptyLabel;

  const _DeckSection({
    required this.title,
    required this.nodes,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (nodes.isEmpty) {
      return Text(
        emptyLabel,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        for (final node in nodes) ...[
          _DeckTreeTile(node: node),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _DeckTreeTile extends ConsumerWidget {
  final DeckTreeNode node;

  const _DeckTreeTile({required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subtitle =
        '${node.dueCards} due \u00b7 ${node.newCards} new \u00b7 ${node.totalCards} total';
    final db = ref.read(appDatabaseProvider);

    if (node.children.isEmpty) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          title: Text(node.deck.title),
          subtitle: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: FilledButton.tonal(
            onPressed: () => showDeckSessionSheet(
              context: context,
              db: db,
              node: node,
              deckIds: _collectDeckIds(node),
            ),
            child: const Text('Start'),
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(node.deck.title),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: FilledButton.tonal(
          onPressed: () => showDeckSessionSheet(
            context: context,
            db: db,
            node: node,
            deckIds: _collectDeckIds(node),
          ),
          child: const Text('Start'),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: [
          for (final child in node.children) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _DeckTreeTile(node: child),
            ),
          ],
        ],
      ),
    );
  }
}

List<String> _collectDeckIds(DeckTreeNode node) {
  final ids = <String>[];
  void walk(DeckTreeNode n) {
    ids.add(n.deck.id);
    for (final child in n.children) {
      walk(child);
    }
  }

  walk(node);
  return ids;
}

extension on _ConceptDetailScreenState {
  Widget _buildTheoryCard(ThemeData theme, Concept concept) {
    final examples = concept.examples.take(2).toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Theory',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: concept.bodyMarkdown.isNotEmpty
                      ? () => setState(
                            () => _theoryExpanded = !_theoryExpanded,
                          )
                      : null,
                  icon: Icon(
                    _theoryExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                  ),
                  label: Text(
                    _theoryExpanded ? 'Hide' : 'Read full theory',
                  ),
                ),
              ],
            ),
            if (concept.summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                concept.summary,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (examples.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final example in examples) ...[
                Text(
                  example['label']?.toString() ?? 'Example',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  example['content']?.toString() ?? '',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
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
        final theoryExercises = matched.where(_isTheoryExercise).toList();
        final practiceExercises = matched.where(_isPracticeExercise).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (theoryExercises.isNotEmpty) ...[
              Text(
                'Learn',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < theoryExercises.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _ExercisePracticeCard(
                  exercise: theoryExercises[i],
                  actionLabel: 'Start Learn',
                ),
              ],
              const SizedBox(height: 24),
            ],
            if (practiceExercises.isNotEmpty) ...[
              Text(
                'Practice',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < practiceExercises.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _ExercisePracticeCard(
                  exercise: practiceExercises[i],
                  actionLabel: 'Start Practice',
                ),
              ],
            ],
          ],
        );
      },
    );
  }

  bool _isTheoryExercise(Exercise exercise) {
    final tags = exercise.tags;
    if (tags.contains('track:theory')) return true;
    if (tags.contains('track:piano')) return false;
    return exercise.inputType != InputType.piano;
  }

  bool _isPracticeExercise(Exercise exercise) {
    final tags = exercise.tags;
    if (tags.contains('track:piano')) return true;
    if (tags.contains('track:theory')) return false;
    return exercise.inputType == InputType.piano;
  }
}

class _ExercisePracticeCard extends ConsumerWidget {
  final Exercise exercise;
  final String actionLabel;

  const _ExercisePracticeCard({
    required this.exercise,
    required this.actionLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final countsAsync = ref.watch(exerciseCountsProvider(exercise.id));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              exercise.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            countsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (counts) {
                final hasDue =
                    counts.reviewCount > 0 || counts.newCount > 0;
                final parts = <String>[];
                if (counts.reviewCount > 0) {
                  parts.add('${counts.reviewCount} due');
                }
                if (counts.newCount > 0) {
                  parts.add('${counts.newCount} new');
                }
                final subtitle = hasDue
                    ? parts.join(' + ')
                    : counts.availableNew > 0
                        ? 'All caught up \u00b7 ${counts.availableNew} to explore'
                        : 'All caught up';
                return Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => SessionBuilderScreen(
                    exerciseId: exercise.id,
                  ),
                ),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
