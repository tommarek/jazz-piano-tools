import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../content/providers/content_providers.dart';
import '../../learn/providers/deck_review_provider.dart';
import '../../learn/widgets/deck_session_sheet.dart';

class EarTrainingScreen extends ConsumerWidget {
  const EarTrainingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decksAsync = ref.watch(allDecksProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ear Training'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: decksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load decks: $error')),
        data: (decks) {
          final rootEarDeckIds = decks
              .where(
                (d) => d.parentId == null && d.tags.contains('modality:ear'),
              )
              .map((d) => d.id)
              .toList()
            ..sort();

          if (rootEarDeckIds.isEmpty) {
            return Center(
              child: Text(
                'No ear training decks available yet.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }

          final treeAsync = ref.watch(deckTreeStatsProvider(rootEarDeckIds));
          return treeAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Failed to load deck stats: $error')),
            data: (nodes) {
              if (nodes.isEmpty) {
                return Center(
                  child: Text(
                    'No ear training decks available yet.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Review interval and listening cards as SRS decks.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final node in nodes) ...[
                    _EarDeckTreeTile(node: node),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _EarDeckTreeTile extends ConsumerWidget {
  final DeckTreeNode node;

  const _EarDeckTreeTile({required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final db = ref.read(appDatabaseProvider);
    final subtitle =
        '${node.dueCards} due · ${node.learnedCards} learned · ${node.totalCards} cards';

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
              ref: ref,
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
            ref: ref,
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
              child: _EarDeckTreeTile(node: child),
            ),
          ],
        ],
      ),
    );
  }
}

List<String> _collectDeckIds(DeckTreeNode node) {
  final ids = <String>[];
  void walk(DeckTreeNode current) {
    ids.add(current.deck.id);
    for (final child in current.children) {
      walk(child);
    }
  }

  walk(node);
  return ids;
}
