import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/library_provider.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(libraryFilterProvider);
    final itemsAsync = ref.watch(libraryItemsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search library...',
              leading: const Icon(Icons.search),
              trailing: _searchController.text.isNotEmpty
                  ? [
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(librarySearchProvider.notifier)
                              .setQuery('');
                          setState(() {});
                        },
                      ),
                    ]
                  : null,
              onChanged: (value) {
                ref.read(librarySearchProvider.notifier).setQuery(value);
                setState(() {});
              },
            ),
          ),

          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: LibraryFilterType.values.map((type) {
                final selected = filter == type;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(_filterLabel(type)),
                    selected: selected,
                    onSelected: (_) {
                      ref
                          .read(libraryFilterProvider.notifier)
                          .setFilter(type);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),

          // Results list
          Expanded(
            child: itemsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text('Failed to load library',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () =>
                          ref.invalidate(libraryItemsProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (items) => _buildItemsList(context, items),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList(BuildContext context, List<LibraryItem> items) {
    final theme = Theme.of(context);

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No items found',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _LibraryItemCard(
          item: item,
          onTap: () => _onItemTap(context, item),
        );
      },
    );
  }

  void _onItemTap(BuildContext context, LibraryItem item) {
    switch (item) {
      case ConceptItem(:final concept):
        context.push('/learn/concept/${concept.id}');
      case ExerciseItem(:final exercise):
        context.push('/session-builder/${exercise.id}');
      case DeckItem():
        // Deck detail screen not yet implemented
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deck: ${item.title}')),
        );
    }
  }

  String _filterLabel(LibraryFilterType type) {
    return switch (type) {
      LibraryFilterType.all => 'All',
      LibraryFilterType.concepts => 'Concepts',
      LibraryFilterType.exercises => 'Exercises',
      LibraryFilterType.decks => 'Decks',
    };
  }
}

class _LibraryItemCard extends ConsumerWidget {
  final LibraryItem item;
  final VoidCallback onTap;

  const _LibraryItemCard({required this.item, required this.onTap});

  IconData get _icon {
    return switch (item) {
      ConceptItem() => Icons.school,
      ExerciseItem() => Icons.fitness_center,
      DeckItem() => Icons.style,
    };
  }

  Color _iconColor(ThemeData theme) {
    return switch (item) {
      ConceptItem() => theme.colorScheme.primary,
      ExerciseItem() => theme.colorScheme.secondary,
      DeckItem() => Colors.teal,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = _iconColor(theme);

    // Fetch counts for exercise items
    ExerciseCounts? counts;
    if (item case ExerciseItem(:final exercise)) {
      final countsAsync = ref.watch(exerciseCountsProvider(exercise.id));
      counts = countsAsync.valueOrNull;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    if (counts != null &&
                        (counts.reviewCount > 0 || counts.newCount > 0))
                      Wrap(
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
                    else if (item.tags.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        children: item.tags
                            .take(3)
                            .map(
                              (tag) => Chip(
                                label: Text(tag),
                                labelStyle: theme.textTheme.labelSmall,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                            )
                            .toList(),
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
