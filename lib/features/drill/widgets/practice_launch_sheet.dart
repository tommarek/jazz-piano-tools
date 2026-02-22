import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/providers/library_provider.dart';
import '../providers/drill_provider.dart';

enum PracticeMode { review, practiceLearned, learn, speedTest }

class PracticeLaunchResult {
  final PracticeMode mode;
  final Set<String>? selectedGroups;
  final int questionCount;
  final int? newCardCount;

  const PracticeLaunchResult({
    required this.mode,
    this.selectedGroups,
    required this.questionCount,
    this.newCardCount,
  });
}

Future<PracticeLaunchResult?> showPracticeLaunchSheet({
  required BuildContext context,
  required String exerciseId,
}) {
  return showModalBottomSheet<PracticeLaunchResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _PracticeLaunchSheet(exerciseId: exerciseId),
  );
}

class _PracticeLaunchSheet extends ConsumerStatefulWidget {
  final String exerciseId;

  const _PracticeLaunchSheet({required this.exerciseId});

  @override
  ConsumerState<_PracticeLaunchSheet> createState() =>
      _PracticeLaunchSheetState();
}

class _PracticeLaunchSheetState extends ConsumerState<_PracticeLaunchSheet> {
  Set<String> _selectedGroups = {};
  int _questionCount = 10;
  int _newCardCount = 5;
  bool _initialized = false;

  static const _countOptions = [5, 10, 15, 20];
  static const _newCardOptions = [5, 10, 15, 20];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exerciseAsync = ref.watch(exerciseByIdProvider(widget.exerciseId));
    final groupCountsAsync =
        ref.watch(exerciseGroupCountsProvider(widget.exerciseId));
    final countsAsync =
        ref.watch(exerciseCountsProvider(widget.exerciseId));

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: exerciseAsync.when(
                data: (exercise) => Text(
                  'Practice: ${exercise.title}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
            ),

            // Scrollable content
            Expanded(
              child: groupCountsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('Error: $error')),
                data: (groups) {
                  if (!_initialized) {
                    _selectedGroups =
                        groups.map((g) => g.groupName).toSet();
                    _initialized = true;
                  }

                  final allGroupNames =
                      groups.map((g) => g.groupName).toSet();
                  final allSelected =
                      _selectedGroups.containsAll(allGroupNames) &&
                          _selectedGroups.length == allGroupNames.length;
                  final totalItemsInSelected = groups
                      .where((g) => _selectedGroups.contains(g.groupName))
                      .fold<int>(0, (sum, g) => sum + g.totalItems);

                  return ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      // Groups header + Select All
                      Row(
                        children: [
                          Text('Groups',
                              style: theme.textTheme.titleMedium),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                if (allSelected) {
                                  _selectedGroups.clear();
                                } else {
                                  _selectedGroups = Set.from(allGroupNames);
                                }
                              });
                            },
                            child: Text(
                                allSelected ? 'Deselect All' : 'Select All'),
                          ),
                        ],
                      ),

                      // Group list
                      for (final group in groups)
                        CheckboxListTile(
                          value:
                              _selectedGroups.contains(group.groupName),
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedGroups.add(group.groupName);
                              } else {
                                _selectedGroups.remove(group.groupName);
                              }
                            });
                          },
                          title: Text(group.groupName),
                          subtitle: Text(
                            '${group.totalItems} items',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          secondary: _buildGroupBadges(theme, group),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                        ),

                      const SizedBox(height: 16),

                      // Question count
                      Text('Questions',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ..._countOptions.map((count) => ChoiceChip(
                                label: Text('$count'),
                                selected: _questionCount == count,
                                onSelected: (_) =>
                                    setState(() => _questionCount = count),
                              )),
                          ChoiceChip(
                            label: Text('All ($totalItemsInSelected)'),
                            selected: !_countOptions
                                .contains(_questionCount) &&
                                _questionCount == totalItemsInSelected,
                            onSelected: (_) => setState(
                                () => _questionCount = totalItemsInSelected),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),
                    ],
                  );
                },
              ),
            ),

            // Mode buttons
            SafeArea(
              top: false,
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: countsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (counts) {
                    final groupCountsValue = ref
                        .watch(exerciseGroupCountsProvider(
                            widget.exerciseId))
                        .valueOrNull;
                    final selectedGroups = groupCountsValue
                            ?.where((g) =>
                                _selectedGroups.contains(g.groupName));
                    final selectedDue = selectedGroups
                            ?.fold<int>(0, (sum, g) => sum + g.dueCount) ??
                        0;
                    final selectedLearned = selectedGroups
                            ?.fold<int>(0, (sum, g) => sum + g.learnedCount) ??
                        0;
                    final newCount = counts.newCount;
                    final availableNew = counts.availableNew;
                    final hasReviewCards =
                        selectedDue > 0 || newCount > 0;
                    final hasLearnedCards = selectedLearned > 0;
                    final hasGroups = _selectedGroups.isNotEmpty;
                    final caughtUpWithNew =
                        !hasReviewCards && hasGroups && availableNew > 0;

                    // Build review button label
                    final reviewParts = <String>[];
                    if (selectedDue > 0) {
                      reviewParts.add('$selectedDue due');
                    }
                    if (newCount > 0) {
                      reviewParts.add('$newCount new');
                    }
                    final reviewLabel = hasReviewCards
                        ? 'Review (${reviewParts.join(' + ')})'
                        : 'Review';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Divider(),
                        const SizedBox(height: 8),
                        if (hasReviewCards)
                          FilledButton(
                            onPressed: () => _launch(PracticeMode.review),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: Text(reviewLabel),
                          ),
                        if (hasReviewCards && hasLearnedCards)
                          const SizedBox(height: 8),
                        if (hasLearnedCards)
                          OutlinedButton(
                            onPressed: () =>
                                _launch(PracticeMode.practiceLearned),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: Text(
                                'Practice Learned ($selectedLearned)'),
                          ),
                        if (caughtUpWithNew) ...[
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'All caught up! Learn some new cards:',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            alignment: WrapAlignment.center,
                            children: _newCardOptions
                                .where((c) => c <= availableNew)
                                .map((count) => ChoiceChip(
                                      label: Text('$count'),
                                      selected: _newCardCount == count,
                                      onSelected: (_) => setState(
                                          () => _newCardCount = count),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: () => _launch(
                              PracticeMode.review,
                              newCardCount: _newCardCount,
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: Text('Learn $_newCardCount New'),
                          ),
                        ],
                        if (!hasReviewCards && !caughtUpWithNew && hasGroups)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'All caught up!',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: hasGroups
                                    ? () => _launch(PracticeMode.learn)
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  minimumSize:
                                      const Size.fromHeight(48),
                                ),
                                child: const Text('Learn'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: hasGroups
                                    ? () =>
                                        _launch(PracticeMode.speedTest)
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  minimumSize:
                                      const Size.fromHeight(48),
                                ),
                                child: const Text('Speed Test'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget? _buildGroupBadges(ThemeData theme, GroupCounts group) {
    final badges = <Widget>[];
    if (group.dueCount > 0) {
      badges.add(_badge(
        '${group.dueCount} due',
        theme.colorScheme.tertiaryContainer,
        theme.colorScheme.onTertiaryContainer,
        theme,
      ));
    }
    if (group.newCount > 0) {
      if (badges.isNotEmpty) badges.add(const SizedBox(width: 4));
      badges.add(_badge(
        '${group.newCount} new',
        theme.colorScheme.primaryContainer,
        theme.colorScheme.onPrimaryContainer,
        theme,
      ));
    }
    if (badges.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: badges);
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

  void _launch(PracticeMode mode, {int? newCardCount}) {
    final allGroupNames = ref
        .read(exerciseGroupCountsProvider(widget.exerciseId))
        .valueOrNull
        ?.map((g) => g.groupName)
        .toSet();
    final allSelected = allGroupNames != null &&
        _selectedGroups.containsAll(allGroupNames) &&
        _selectedGroups.length == allGroupNames.length;

    Navigator.of(context).pop(PracticeLaunchResult(
      mode: mode,
      selectedGroups: allSelected ? null : Set.from(_selectedGroups),
      questionCount: _questionCount,
      newCardCount: newCardCount,
    ));
  }
}
