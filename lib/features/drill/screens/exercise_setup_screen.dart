import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/providers/library_provider.dart';
import '../providers/drill_provider.dart';
import 'drill_screen.dart';
import 'practice_screen.dart';

class ExerciseSetupScreen extends ConsumerStatefulWidget {
  final String exerciseId;

  const ExerciseSetupScreen({required this.exerciseId, super.key});

  @override
  ConsumerState<ExerciseSetupScreen> createState() =>
      _ExerciseSetupScreenState();
}

class _ExerciseSetupScreenState extends ConsumerState<ExerciseSetupScreen> {
  final Set<String> _selectedGroups = {};
  bool _allSelected = true;

  @override
  Widget build(BuildContext context) {
    final exerciseAsync = ref.watch(exerciseByIdProvider(widget.exerciseId));
    final groupCountsAsync =
        ref.watch(exerciseGroupCountsProvider(widget.exerciseId));

    return Scaffold(
      appBar: AppBar(
        title: exerciseAsync.when(
          data: (exercise) => Text(exercise.title),
          loading: () => const Text('Loading...'),
          error: (_, _) => const Text('Exercise'),
        ),
      ),
      body: groupCountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (groups) {
          if (_selectedGroups.isEmpty && _allSelected) {
            // Initialize: select all groups
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _selectedGroups.isEmpty) {
                setState(() {
                  _selectedGroups
                      .addAll(groups.map((g) => g.groupName));
                });
              }
            });
          }
          return _buildBody(context, groups);
        },
      ),
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  Widget _buildBody(BuildContext context, List<GroupCounts> groups) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Select All / Deselect All
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Text('Groups', style: theme.textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_selectedGroups.length == groups.length) {
                      _selectedGroups.clear();
                      _allSelected = false;
                    } else {
                      _selectedGroups.clear();
                      _selectedGroups
                          .addAll(groups.map((g) => g.groupName));
                      _allSelected = true;
                    }
                  });
                },
                child: Text(
                  _selectedGroups.length == groups.length
                      ? 'Deselect All'
                      : 'Select All',
                ),
              ),
            ],
          ),
        ),

        // Group list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              final selected = _selectedGroups.contains(group.groupName);
              return _GroupCard(
                group: group,
                selected: selected,
                onToggle: () {
                  setState(() {
                    if (selected) {
                      _selectedGroups.remove(group.groupName);
                      _allSelected = false;
                    } else {
                      _selectedGroups.add(group.groupName);
                      if (_selectedGroups.length == groups.length) {
                        _allSelected = true;
                      }
                    }
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelection = _selectedGroups.isNotEmpty;

    return SafeArea(
      top: false,
      child: Material(
        elevation: 6,
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: hasSelection
                    ? () => _startMode(context, 'practice')
                    : null,
                icon: const Icon(Icons.fitness_center),
                label: const Text('Practice'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: hasSelection
                          ? () => _startMode(context, 'drillHard')
                          : null,
                      icon: const Icon(Icons.local_fire_department),
                      label: const Text('Drill Hard'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: hasSelection
                          ? () => _startMode(context, 'test')
                          : null,
                      icon: const Icon(Icons.timer),
                      label: const Text('Drill'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startMode(BuildContext context, String mode) {
    final groups = _allSelected ? null : _selectedGroups;
    switch (mode) {
      case 'practice':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PracticeScreen(
              exerciseId: widget.exerciseId,
              selectedGroups: groups,
            ),
          ),
        );
      case 'drillHard':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DrillScreen(
              exerciseId: widget.exerciseId,
              selectedGroups: groups,
              hardOnly: true,
            ),
          ),
        );
      case 'test':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DrillScreen(
              exerciseId: widget.exerciseId,
              selectedGroups: groups,
            ),
          ),
        );
    }
  }
}

class _GroupCard extends StatelessWidget {
  final GroupCounts group;
  final bool selected;
  final VoidCallback onToggle;

  const _GroupCard({
    required this.group,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.groupName,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${group.totalItems} items',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 6,
                children: [
                  if (group.dueCount > 0)
                    _badge(
                      '${group.dueCount} due',
                      theme.colorScheme.tertiaryContainer,
                      theme.colorScheme.onTertiaryContainer,
                      theme,
                    ),
                  if (group.newCount > 0)
                    _badge(
                      '${group.newCount} new',
                      theme.colorScheme.primaryContainer,
                      theme.colorScheme.onPrimaryContainer,
                      theme,
                    ),
                  if (group.learnedCount > 0 &&
                      group.dueCount == 0 &&
                      group.newCount == 0)
                    _badge(
                      '${group.learnedCount} learned',
                      theme.colorScheme.surfaceContainerHighest,
                      theme.colorScheme.onSurfaceVariant,
                      theme,
                    ),
                ],
              ),
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
