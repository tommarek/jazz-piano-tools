import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

import '../../../app/providers.dart';
import '../../../database/app_database.dart' hide Card;
import '../../library/providers/library_provider.dart';
import '../providers/drill_provider.dart';
import '../providers/session_templates_provider.dart';
import '../widgets/session_summary_card.dart';
import 'drill_screen.dart';
import 'learn_screen.dart';
import 'practice_screen.dart';

enum SessionMode {
  review,
  practiceLearned,
  learn,
  speedTest,
  drillHard,
}

class SessionBuilderScreen extends ConsumerStatefulWidget {
  final String exerciseId;

  const SessionBuilderScreen({required this.exerciseId, super.key});

  @override
  ConsumerState<SessionBuilderScreen> createState() =>
      _SessionBuilderScreenState();
}

class _SessionBuilderScreenState
    extends ConsumerState<SessionBuilderScreen> {
  SessionMode _mode = SessionMode.review;
  Set<String> _selectedGroups = {};
  bool _initialized = false;
  int _questionCount = 10;
  int _newCardCount = 5;
  int? _timeLimitSeconds;
  int _quickStartCount = 0;
  int? _lastQuickStartAt;
  String? _lastTemplateKey;
  int? _lastTemplateUsedAt;
  String? _lastTemplateTitle;

  static const _questionOptions = [5, 10, 15, 20];
  static const _newCardOptions = [5, 10, 15, 20];
  static const _timeOptions = [60, 90, 120, 180];
  static const _uuid = Uuid();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });
  }

  Future<void> _loadSettings() async {
    final db = ref.read(appDatabaseProvider);
    final settings = await db.settingsDao.getSettings();
    if (!mounted) return;
    setState(() {
      _timeLimitSeconds = settings?.drillTimeLimitSeconds ?? 120;
      _quickStartCount = settings?.quickStartCount ?? 0;
      _lastQuickStartAt = settings?.lastQuickStartAt;
      _lastTemplateKey = settings?.lastTemplateKey;
      _lastTemplateUsedAt = settings?.lastTemplateUsedAt;
    });
  }

  @override
  Widget build(BuildContext context) {
    final exerciseAsync = ref.watch(exerciseByIdProvider(widget.exerciseId));
    final groupCountsAsync =
        ref.watch(exerciseGroupCountsProvider(widget.exerciseId));
    final countsAsync = ref.watch(exerciseCountsProvider(widget.exerciseId));
    final templatesAsync =
        ref.watch(sessionTemplatesProvider(widget.exerciseId));

    return Scaffold(
      appBar: AppBar(
        title: exerciseAsync.when(
          data: (exercise) => Text(exercise.title),
          loading: () => const Text('Session Builder'),
          error: (_, _) => const Text('Session Builder'),
        ),
      ),
      body: groupCountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (groups) {
          if (!_initialized) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _selectedGroups = groups.map((g) => g.groupName).toSet();
                _initialized = true;
                _clampQuestionCount(groups);
              });
            });
          }
          return countsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Error: $error')),
            data: (counts) => templatesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Error: $error')),
              data: (templates) =>
                  _buildBody(context, groups, counts, templates),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<GroupCounts> groups,
    ExerciseCounts counts,
    List<SessionTemplate> templates,
  ) {
    final theme = Theme.of(context);

    final selectedGroups =
        groups.where((g) => _selectedGroups.contains(g.groupName)).toList();
    final selectedDue =
        selectedGroups.fold<int>(0, (sum, g) => sum + g.dueCount);
    final selectedLearned =
        selectedGroups.fold<int>(0, (sum, g) => sum + g.learnedCount);
    final selectedAvailableNew =
        selectedGroups.fold<int>(0, (sum, g) => sum + g.newCount);
    final selectedTotalItems =
        selectedGroups.fold<int>(0, (sum, g) => sum + g.totalItems);

    final dailyNewSlots = counts.newCount;
    final maxNew = math.min(dailyNewSlots, selectedAvailableNew);
    final effectiveNew = math.min(_newCardCount, maxNew);

    final hasGroups = _selectedGroups.isNotEmpty;
    final showQuestionCount =
        _mode == SessionMode.learn || _mode == SessionMode.speedTest;
    final showTimeLimit =
        _mode == SessionMode.speedTest || _mode == SessionMode.drillHard;
    final showNewCards = _mode == SessionMode.review;

    final summaryLines = <String>[];
    summaryLines.add(_modeLabel(_mode));
    summaryLines.add(
      _selectedGroups.length == groups.length
          ? 'Groups: All'
          : 'Groups: ${_selectedGroups.length} selected',
    );
    if (_mode == SessionMode.review) {
      final parts = <String>[];
      if (selectedDue > 0) parts.add('$selectedDue due');
      if (effectiveNew > 0) parts.add('$effectiveNew new');
      if (parts.isEmpty) {
        parts.add('All caught up');
      }
      summaryLines.add('Queue: ${parts.join(' + ')}');
    }
    if (_mode == SessionMode.practiceLearned) {
      summaryLines.add('Learned: $selectedLearned');
    }
    if (showQuestionCount) {
      summaryLines.add('Questions: $_questionCount');
    }
    if (showTimeLimit) {
      final seconds = _timeLimitSeconds ?? 120;
      summaryLines.add('Time limit: ${_formatDurationLabel(seconds)}');
    }

    final canReview = selectedDue > 0 || maxNew > 0;
    final canLearn = selectedTotalItems > 0;
    final canStart = hasGroups &&
        switch (_mode) {
          SessionMode.review => canReview,
          SessionMode.practiceLearned => selectedLearned > 0,
          SessionMode.learn => canLearn,
          SessionMode.speedTest => canLearn,
          SessionMode.drillHard => canLearn,
        };
    final lastPresetLabel = _buildLastPresetLabel(
      templates: templates,
    );

    final sessionSizeCard = Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showQuestionCount) ...[
              Text('Questions', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _buildQuestionChips(selectedTotalItems),
              const SizedBox(height: 16),
            ],
            if (showTimeLimit) ...[
              Text('Time Limit', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _buildTimeChips(),
              const SizedBox(height: 16),
            ],
            if (showNewCards) ...[
              Text('New Cards', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _buildNewCardChips(maxNew),
            ],
            if (!showQuestionCount && !showTimeLimit && !showNewCards)
              Text(
                'This mode uses all available items.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );

    final startButton = FilledButton(
      onPressed: canStart ? () => _startSession(effectiveNew) : null,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      child: Text(_startLabel(_mode)),
    );

    final noGroupsHint = !hasGroups
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Select at least one group to continue.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          )
        : const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;

        final leftWidgets = <Widget>[
          _buildSectionTitle(theme, 'Quick Start'),
          const SizedBox(height: 8),
          _buildQuickStartCard(
            selectedDue: selectedDue,
            effectiveNew: effectiveNew,
            groupsCount: _selectedGroups.length,
            totalGroups: groups.length,
            canStart: hasGroups && canReview,
          ),
          const SizedBox(height: 16),
          _buildSectionTitle(theme, 'Start'),
          const SizedBox(height: 8),
          _buildPrimaryModeCard(
            groups: groups,
            selectedDue: selectedDue,
            maxNew: maxNew,
            canLearn: canLearn,
            canReview: canReview,
          ),
          const SizedBox(height: 8),
          _buildAdvancedModes(
            groups: groups,
            selectedLearned: selectedLearned,
            canLearn: canLearn,
          ),
          const SizedBox(height: 16),
          _buildSectionTitle(theme, 'Scope'),
          const SizedBox(height: 8),
          _buildGroupSelector(context, groups),
          const SizedBox(height: 16),
          _buildSectionTitle(theme, 'Templates'),
          const SizedBox(height: 8),
          _buildTemplates(
            templates: templates,
            totalItems: selectedTotalItems,
            maxNew: maxNew,
          ),
        ];

        final rightWidgets = <Widget>[
          _buildSectionTitle(theme, 'Session Options'),
          const SizedBox(height: 8),
          sessionSizeCard,
          const SizedBox(height: 16),
          SessionSummaryCard(
            title: 'Summary',
            lines: summaryLines,
          ),
          if (lastPresetLabel != null) ...[
            const SizedBox(height: 8),
            _buildLastPresetBadge(theme, lastPresetLabel),
          ],
          const SizedBox(height: 16),
          startButton,
          noGroupsHint,
        ];

        if (!isWide) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...leftWidgets,
              const SizedBox(height: 16),
              ...rightWidgets,
            ],
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: leftWidgets,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rightWidgets,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Text(title, style: theme.textTheme.titleMedium);
  }

  Widget _buildQuickStartCard({
    required int selectedDue,
    required int effectiveNew,
    required int groupsCount,
    required int totalGroups,
    required bool canStart,
  }) {
    final theme = Theme.of(context);
    final parts = <String>[];
    if (selectedDue > 0) parts.add('$selectedDue due');
    if (effectiveNew > 0) parts.add('$effectiveNew new');
    if (parts.isEmpty) parts.add('All caught up');
    final groupLabel =
        groupsCount == totalGroups ? 'All groups' : '$groupsCount groups';
    final analyticsLabel = _quickStartCount > 0
        ? 'Used $_quickStartCount times${_formatLastUsed(_lastQuickStartAt)}'
        : 'Not used yet';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Review now',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${parts.join(' + ')} \u00b7 $groupLabel',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              analyticsLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: canStart ? () => _quickStart(effectiveNew) : null,
              child: const Text('Start Review Now'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryModeCard({
    required List<GroupCounts> groups,
    required int selectedDue,
    required int maxNew,
    required bool canLearn,
    required bool canReview,
  }) {
    final theme = Theme.of(context);
    final reviewSubtitle = canReview
        ? '${selectedDue} due \u00b7 ${maxNew} new'
        : 'All caught up';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _ModeCta(
                title: 'Learn',
                subtitle: 'Theory flashcards',
                selected: _mode == SessionMode.learn,
                enabled: canLearn,
                onTap: () => setState(() {
                  _mode = SessionMode.learn;
                  _clampQuestionCount(groups);
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ModeCta(
                title: 'Practice',
                subtitle: reviewSubtitle,
                selected: _mode == SessionMode.review,
                enabled: canReview,
                onTap: () => setState(() {
                  _mode = SessionMode.review;
                  _clampQuestionCount(groups);
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedModes({
    required List<GroupCounts> groups,
    required int selectedLearned,
    required bool canLearn,
  }) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: const Text('More options'),
        subtitle: Text(
          'Practice Learned, Speed Test, Drill Hard',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          _ModeTile(
            title: 'Practice Learned',
            subtitle: 'Review learned items',
            selected: _mode == SessionMode.practiceLearned,
            enabled: selectedLearned > 0,
            onTap: () => setState(() {
              _mode = SessionMode.practiceLearned;
              _clampQuestionCount(groups);
            }),
          ),
          _ModeTile(
            title: 'Speed Test',
            subtitle: 'Timed drill with score',
            selected: _mode == SessionMode.speedTest,
            enabled: canLearn,
            onTap: () => setState(() {
              _mode = SessionMode.speedTest;
              _clampQuestionCount(groups);
            }),
          ),
          _ModeTile(
            title: 'Drill Hard',
            subtitle: 'Focus on hard items',
            selected: _mode == SessionMode.drillHard,
            enabled: canLearn,
            onTap: () => setState(() {
              _mode = SessionMode.drillHard;
              _clampQuestionCount(groups);
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplates({
    required List<SessionTemplate> templates,
    required int totalItems,
    required int maxNew,
  }) {
    final theme = Theme.of(context);
    final builtinTemplates = _builtinTemplates();

    final customTemplates = templates.toList()
      ..sort((a, b) {
        final aKey = (a.folder ?? '').toLowerCase();
        final bKey = (b.folder ?? '').toLowerCase();
        final folderCompare = aKey.compareTo(bKey);
        if (folderCompare != 0) return folderCompare;
        return b.updatedAt.compareTo(a.updatedAt);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () => _showTemplateEditor(),
          icon: const Icon(Icons.add),
          label: const Text('Create Template'),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < builtinTemplates.length; i++) ...[
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              title: Text(builtinTemplates[i].title),
              subtitle: Text(
                builtinTemplates[i].subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_lastTemplateKey == builtinTemplates[i].key &&
                      _lastTemplateUsedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        'Last used${_formatLastUsed(_lastTemplateUsedAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  FilledButton.tonal(
                    onPressed: () => _startTemplate(
                      template: builtinTemplates[i],
                      totalItems: totalItems,
                      maxNew: maxNew,
                    ),
                    child: const Text('Start'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (customTemplates.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Custom Templates',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < customTemplates.length; i++) ...[
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                title: Text(customTemplates[i].title),
                subtitle: Text(
                  _customTemplateSubtitle(customTemplates[i]),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    if (_lastTemplateKey == customTemplates[i].id &&
                        _lastTemplateUsedAt != null)
                      Text(
                        'Last used${_formatLastUsed(_lastTemplateUsedAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _showTemplateEditor(
                        existing: customTemplates[i],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDeleteTemplate(customTemplates[i]),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _startCustomTemplate(
                        template: customTemplates[i],
                        totalItems: totalItems,
                        maxNew: maxNew,
                      ),
                      child: const Text('Start'),
                    ),
                  ],
                ),
              ),
            ),
            if (i < customTemplates.length - 1) const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _buildModeCard(
    BuildContext context,
    List<GroupCounts> groups, {
    required int selectedDue,
    required int selectedLearned,
    required int maxNew,
  }) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _ModeTile(
            title: 'Review (SRS)',
            subtitle: _reviewSubtitle(selectedDue, maxNew),
            selected: _mode == SessionMode.review,
            enabled: true,
            onTap: () => setState(() {
              _mode = SessionMode.review;
              _clampQuestionCount(groups);
            }),
          ),
          _divider(theme),
          _ModeTile(
            title: 'Practice Learned',
            subtitle: selectedLearned > 0
                ? '$selectedLearned learned'
                : 'No learned items yet',
            selected: _mode == SessionMode.practiceLearned,
            enabled: true,
            onTap: () => setState(() {
              _mode = SessionMode.practiceLearned;
              _clampQuestionCount(groups);
            }),
          ),
          _divider(theme),
          _ModeTile(
            title: 'Learn (Flashcards)',
            subtitle: 'No scoring, reveal answers',
            selected: _mode == SessionMode.learn,
            enabled: true,
            onTap: () => setState(() {
              _mode = SessionMode.learn;
              _clampQuestionCount(groups);
            }),
          ),
          _divider(theme),
          _ModeTile(
            title: 'Speed Test',
            subtitle: 'Timed drill with score',
            selected: _mode == SessionMode.speedTest,
            enabled: true,
            onTap: () => setState(() {
              _mode = SessionMode.speedTest;
              _clampQuestionCount(groups);
            }),
          ),
          _divider(theme),
          _ModeTile(
            title: 'Drill Hard',
            subtitle: 'Focus on hard items only',
            selected: _mode == SessionMode.drillHard,
            enabled: true,
            onTap: () => setState(() {
              _mode = SessionMode.drillHard;
              _clampQuestionCount(groups);
            }),
          ),
        ],
      ),
    );
  }

  Widget _divider(ThemeData theme) {
    return Divider(height: 1, color: theme.colorScheme.outlineVariant);
  }

  String _reviewSubtitle(int selectedDue, int maxNew) {
    final parts = <String>[];
    if (selectedDue > 0) parts.add('$selectedDue due');
    if (maxNew > 0) parts.add('$maxNew new');
    if (parts.isEmpty) return 'All caught up';
    return parts.join(' + ');
  }

  Widget _buildGroupSelector(BuildContext context, List<GroupCounts> groups) {
    final theme = Theme.of(context);
    final allGroupNames = groups.map((g) => g.groupName).toSet();
    final allSelected =
        _selectedGroups.containsAll(allGroupNames) &&
            _selectedGroups.length == allGroupNames.length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text('Groups', style: theme.textTheme.titleSmall),
        subtitle: Text(
          '${_selectedGroups.length} selected',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Row(
            children: [
              TextButton(
                onPressed: () {
                  setState(() {
                    if (allSelected) {
                      _selectedGroups.clear();
                    } else {
                      _selectedGroups = Set.from(allGroupNames);
                    }
                    _clampQuestionCount(groups);
                  });
                },
                child: Text(allSelected ? 'Deselect All' : 'Select All'),
              ),
              const Spacer(),
              Text(
                '${groups.length} groups',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final group in groups)
            CheckboxListTile(
              value: _selectedGroups.contains(group.groupName),
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _selectedGroups.add(group.groupName);
                  } else {
                    _selectedGroups.remove(group.groupName);
                  }
                  _clampQuestionCount(groups);
                });
              },
              title: Text(group.groupName),
              subtitle: Text(
                _groupSubtitle(group),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
        ],
      ),
    );
  }

  String _groupSubtitle(GroupCounts group) {
    final parts = <String>['${group.totalItems} items'];
    if (group.dueCount > 0) parts.add('${group.dueCount} due');
    if (group.newCount > 0) parts.add('${group.newCount} new');
    if (group.learnedCount > 0 && group.dueCount == 0 && group.newCount == 0) {
      parts.add('${group.learnedCount} learned');
    }
    return parts.join(' | ');
  }

  Widget _buildQuestionChips(int totalItems) {
    final options = _questionOptions
        .where((n) => totalItems == 0 || n <= totalItems)
        .toList();
    final allLabel = totalItems > 0 ? 'All ($totalItems)' : 'All';

    return Wrap(
      spacing: 8,
      children: [
        ...options.map(
          (count) => ChoiceChip(
            label: Text('$count'),
            selected: _questionCount == count,
            onSelected: (_) => setState(() => _questionCount = count),
          ),
        ),
        ChoiceChip(
          label: Text(allLabel),
          selected: totalItems > 0 && _questionCount == totalItems,
          onSelected: totalItems > 0
              ? (_) => setState(() => _questionCount = totalItems)
              : null,
        ),
      ],
    );
  }

  Widget _buildNewCardChips(int maxNew) {
    final theme = Theme.of(context);
    if (maxNew <= 0) {
      return Text(
        'No new cards available today.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final options = _newCardOptions.where((n) => n <= maxNew).toList();
    return Wrap(
      spacing: 8,
      children: [
        ...options.map(
          (count) => ChoiceChip(
            label: Text('$count'),
            selected: _newCardCount == count,
            onSelected: (_) => setState(() => _newCardCount = count),
          ),
        ),
        ChoiceChip(
          label: Text('All ($maxNew)'),
          selected: _newCardCount == maxNew,
          onSelected: (_) => setState(() => _newCardCount = maxNew),
        ),
      ],
    );
  }

  Widget _buildTimeChips() {
    final seconds = _timeLimitSeconds ?? 120;
    return Wrap(
      spacing: 8,
      children: [
        ..._timeOptions.map(
          (option) => ChoiceChip(
            label: Text(_formatDurationLabel(option)),
            selected: seconds == option,
            onSelected: (_) => setState(() => _timeLimitSeconds = option),
          ),
        ),
      ],
    );
  }

  String _modeLabel(SessionMode mode) {
    return switch (mode) {
      SessionMode.review => 'Mode: Review (SRS)',
      SessionMode.practiceLearned => 'Mode: Practice Learned',
      SessionMode.learn => 'Mode: Learn (Flashcards)',
      SessionMode.speedTest => 'Mode: Speed Test',
      SessionMode.drillHard => 'Mode: Drill Hard',
    };
  }

  String _formatDurationLabel(int seconds) {
    if (seconds < 60) return '${seconds}s';
    return '${seconds ~/ 60} min';
  }

  String _startLabel(SessionMode mode) {
    return switch (mode) {
      SessionMode.review => 'Start Review',
      SessionMode.practiceLearned => 'Start Practice',
      SessionMode.learn => 'Start Learn',
      SessionMode.speedTest => 'Start Speed Test',
      SessionMode.drillHard => 'Start Drill Hard',
    };
  }

  void _startSession(int effectiveNew) {
    _startSessionWithMode(_mode, effectiveNew);
  }

  void _quickStart(int effectiveNew) {
    if (_selectedGroups.isEmpty) return;
    setState(() {
      _mode = SessionMode.review;
    });
    _recordQuickStart();
    _startSessionWithMode(SessionMode.review, effectiveNew);
  }

  void _startTemplate({
    required _SessionTemplate template,
    required int totalItems,
    required int maxNew,
  }) {
    _lastTemplateTitle = template.title;
    _recordTemplateUse(template.key);
    final effectiveQuestion = template.questionCount != null && totalItems > 0
        ? math.min(template.questionCount!, totalItems)
        : template.questionCount;
    final effectiveNew = template.newCardCount != null
        ? math.min(template.newCardCount!, maxNew)
        : null;

    setState(() {
      _mode = template.mode;
      if (effectiveQuestion != null) _questionCount = effectiveQuestion;
      if (template.timeLimitSeconds != null) {
        _timeLimitSeconds = template.timeLimitSeconds;
      }
      if (effectiveNew != null) _newCardCount = effectiveNew;
    });

    _startSessionWithMode(
      template.mode,
      effectiveNew ?? math.min(_newCardCount, maxNew),
    );
  }

  void _startCustomTemplate({
    required SessionTemplate template,
    required int totalItems,
    required int maxNew,
  }) {
    _lastTemplateTitle = template.title;
    final mode = _modeFromString(template.mode);
    final effectiveQuestion = template.questionCount != null && totalItems > 0
        ? math.min(template.questionCount!, totalItems)
        : template.questionCount;
    final effectiveNew = template.newCardCount != null
        ? math.min(template.newCardCount!, maxNew)
        : null;

    setState(() {
      _mode = mode;
      if (effectiveQuestion != null) _questionCount = effectiveQuestion;
      if (template.timeLimitSeconds != null) {
        _timeLimitSeconds = template.timeLimitSeconds;
      }
      if (effectiveNew != null) _newCardCount = effectiveNew;
    });

    _recordTemplateUse(template.id);
    _startSessionWithMode(
      mode,
      effectiveNew ?? math.min(_newCardCount, maxNew),
    );
  }

  Future<void> _startSessionWithMode(SessionMode mode, int effectiveNew) async {
    final groups = _selectedGroups;
    final selectedGroups = groups.isEmpty ? null : Set<String>.from(groups);

    Widget screen;
    switch (mode) {
      case SessionMode.review:
        screen = PracticeScreen(
          exerciseId: widget.exerciseId,
          selectedGroups: selectedGroups,
          newCardCount: effectiveNew > 0 ? effectiveNew : null,
        );
      case SessionMode.practiceLearned:
        screen = PracticeScreen(
          exerciseId: widget.exerciseId,
          selectedGroups: selectedGroups,
          learnedOnly: true,
        );
      case SessionMode.learn:
        screen = ExerciseLearnScreen(
          exerciseId: widget.exerciseId,
          selectedGroups: selectedGroups,
          questionCount: _questionCount,
        );
      case SessionMode.speedTest:
        screen = DrillScreen(
          exerciseId: widget.exerciseId,
          selectedGroups: selectedGroups,
          questionCount: _questionCount,
          timeLimitSeconds: _timeLimitSeconds,
        );
      case SessionMode.drillHard:
        screen = DrillScreen(
          exerciseId: widget.exerciseId,
          selectedGroups: selectedGroups,
          hardOnly: true,
          timeLimitSeconds: _timeLimitSeconds,
        );
    }

    await Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    ref.invalidate(exerciseCountsProvider(widget.exerciseId));
    ref.invalidate(exerciseGroupCountsProvider(widget.exerciseId));
  }

  void _clampQuestionCount(List<GroupCounts> groups) {
    if (_mode != SessionMode.learn && _mode != SessionMode.speedTest) return;
    final selectedGroups =
        groups.where((g) => _selectedGroups.contains(g.groupName));
    final totalItems =
        selectedGroups.fold<int>(0, (sum, g) => sum + g.totalItems);
    if (totalItems <= 0) return;
    if (_questionCount > totalItems) {
      _questionCount = totalItems;
    }
  }

  SessionMode _modeFromString(String value) {
    return SessionMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => SessionMode.review,
    );
  }

  String _formatLastUsed(int? epochMillis) {
    if (epochMillis == null) return '';
    final now = DateTime.now();
    final then = DateTime.fromMillisecondsSinceEpoch(epochMillis);
    final diff = now.difference(then);
    if (diff.inMinutes < 1) return ' • just now';
    if (diff.inMinutes < 60) return ' • ${diff.inMinutes} min ago';
    if (diff.inHours < 24) return ' • ${diff.inHours} hr ago';
    if (diff.inDays < 7) return ' • ${diff.inDays} d ago';
    return ' • ${then.month}/${then.day}/${then.year}';
  }

  Future<void> _recordQuickStart() async {
    final db = ref.read(appDatabaseProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    final nextCount = _quickStartCount + 1;
    await db.settingsDao.upsertSettings(
      SettingsCompanion(
        quickStartCount: Value(nextCount),
        lastQuickStartAt: Value(now),
      ),
    );
    if (!mounted) return;
    setState(() {
      _quickStartCount = nextCount;
      _lastQuickStartAt = now;
    });
  }

  Future<void> _recordTemplateUse(String key) async {
    final db = ref.read(appDatabaseProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.settingsDao.upsertSettings(
      SettingsCompanion(
        lastTemplateKey: Value(key),
        lastTemplateUsedAt: Value(now),
      ),
    );
    if (!mounted) return;
    setState(() {
      _lastTemplateKey = key;
      _lastTemplateUsedAt = now;
    });
  }

  String _templateSubtitleFromRow(SessionTemplate template) {
    final mode = _modeFromString(template.mode);
    return switch (mode) {
      SessionMode.review => 'Review with new cards',
      SessionMode.practiceLearned => 'Review learned items',
      SessionMode.learn => 'Flashcards, no scoring',
      SessionMode.speedTest => 'Timed drill with score',
      SessionMode.drillHard => 'Focus on hard items',
    };
  }

  String _customTemplateSubtitle(SessionTemplate template) {
    final base = template.subtitle.isNotEmpty
        ? template.subtitle
        : _templateSubtitleFromRow(template);
    final extras = <String>[];
    if (template.folder != null && template.folder!.isNotEmpty) {
      extras.add('Folder: ${template.folder}');
    }
    if (template.tags != null && template.tags!.isNotEmpty) {
      extras.add('Tags: ${template.tags}');
    }
    if (template.isGlobal == true) extras.add('Shared');
    if (extras.isEmpty) return base;
    return '$base • ${extras.join(' • ')}';
  }

  String? _buildLastPresetLabel({
    required List<SessionTemplate> templates,
  }) {
    if (_lastTemplateKey != null && _lastTemplateUsedAt != null) {
      final builtin = _builtinTemplates()
          .firstWhereOrNull((t) => t.key == _lastTemplateKey);
      final name = builtin?.title ??
          templates
              .firstWhereOrNull((t) => t.id == _lastTemplateKey)
              ?.title ??
          _lastTemplateTitle;
      if (name != null && name.isNotEmpty) {
        return 'Last used preset: $name${_formatLastUsed(_lastTemplateUsedAt)}';
      }
    }
    if (_lastQuickStartAt != null) {
      return 'Last used: Quick Start${_formatLastUsed(_lastQuickStartAt)}';
    }
    return null;
  }

  Widget _buildLastPresetBadge(ThemeData theme, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteTemplate(SessionTemplate template) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete template?'),
        content: Text('Delete "${template.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      final db = ref.read(appDatabaseProvider);
      await db.sessionTemplatesDao.deleteTemplate(template.id);
    }
  }

  Future<void> _showTemplateEditor({SessionTemplate? existing}) async {
    final titleController =
        TextEditingController(text: existing?.title ?? '');
    final subtitleController =
        TextEditingController(text: existing?.subtitle ?? '');
    final folderController =
        TextEditingController(text: existing?.folder ?? '');
    final tagsController =
        TextEditingController(text: existing?.tags ?? '');
    final questionController = TextEditingController(
      text: existing?.questionCount?.toString() ?? '',
    );
    final newCardController = TextEditingController(
      text: existing?.newCardCount?.toString() ?? '',
    );
    final timeController = TextEditingController(
      text: existing?.timeLimitSeconds != null
          ? (existing!.timeLimitSeconds! ~/ 60).toString()
          : '',
    );

    SessionMode mode =
        existing != null ? _modeFromString(existing.mode) : _mode;
    bool isGlobal = existing?.isGlobal ?? false;
    bool initialized = false;
    String? titleError;
    String? questionError;
    String? newCardError;
    String? timeError;

    int? parseOptionalInt(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      return int.tryParse(trimmed);
    }

    String? validatePositiveInt(String raw, {required bool required}) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return required ? 'Required' : null;
      final value = int.tryParse(trimmed);
      if (value == null) return 'Enter a number';
      if (value <= 0) return 'Must be > 0';
      return null;
    }

    void updateValidation(
      StateSetter setSheetState, {
      required bool showQuestion,
      required bool showTime,
      required bool showNew,
    }) {
      final nextTitleError =
          titleController.text.trim().isEmpty ? 'Title required' : null;
      final nextQuestionError = showQuestion
          ? validatePositiveInt(questionController.text, required: true)
          : null;
      final nextTimeError =
          showTime ? validatePositiveInt(timeController.text, required: false) : null;
      final nextNewCardError =
          showNew
              ? validatePositiveInt(newCardController.text, required: false)
              : null;
      setSheetState(() {
        titleError = nextTitleError;
        questionError = nextQuestionError;
        timeError = nextTimeError;
        newCardError = nextNewCardError;
      });
    }

    Future<void> saveTemplate(StateSetter setSheetState) async {
      final title = titleController.text.trim();
      if (title.isEmpty) return;
      final subtitle = subtitleController.text.trim();
      final folder = folderController.text.trim();
      final tags = tagsController.text.trim();
      final questionCount = parseOptionalInt(questionController.text);
      final newCardCount = parseOptionalInt(newCardController.text);
      final timeMinutes = parseOptionalInt(timeController.text);
      final timeLimitSeconds =
          timeMinutes != null && timeMinutes > 0 ? timeMinutes * 60 : null;
      final requiresQuestion =
          mode == SessionMode.learn || mode == SessionMode.speedTest;
      if (requiresQuestion && questionCount == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = existing?.id ?? _uuid.v4();
      final createdAt = existing?.createdAt ?? now;
      final exerciseId = isGlobal ? null : widget.exerciseId;

      final db = ref.read(appDatabaseProvider);
      await db.sessionTemplatesDao.upsertTemplate(
        SessionTemplatesCompanion(
          id: Value(id),
          exerciseId: Value(exerciseId),
          title: Value(title),
          subtitle: Value(subtitle),
          mode: Value(mode.name),
          questionCount: Value(questionCount),
          newCardCount: Value(newCardCount),
          timeLimitSeconds: Value(timeLimitSeconds),
          folder: Value(folder.isEmpty ? null : folder),
          tags: Value(tags.isEmpty ? null : tags),
          isGlobal: Value(isGlobal),
          createdAt: Value(createdAt),
          updatedAt: Value(now),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final showQuestion = mode == SessionMode.learn ||
                mode == SessionMode.speedTest;
            final showTime =
                mode == SessionMode.speedTest || mode == SessionMode.drillHard;
            final showNew = mode == SessionMode.review;
            if (!initialized) {
              titleError =
                  titleController.text.trim().isEmpty ? 'Title required' : null;
              questionError = showQuestion
                  ? validatePositiveInt(questionController.text, required: true)
                  : null;
              timeError =
                  showTime
                      ? validatePositiveInt(timeController.text, required: false)
                      : null;
              newCardError =
                  showNew
                      ? validatePositiveInt(newCardController.text,
                          required: false)
                      : null;
              initialized = true;
            }
            final canSave = titleError == null &&
                questionError == null &&
                timeError == null &&
                newCardError == null;

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                top: 8,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    existing == null ? 'Create Template' : 'Edit Template',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: 'Title',
                      errorText: titleError,
                    ),
                    onChanged: (_) => updateValidation(
                      setSheetState,
                      showQuestion: showQuestion,
                      showTime: showTime,
                      showNew: showNew,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subtitleController,
                    decoration: const InputDecoration(
                      labelText: 'Subtitle (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: folderController,
                    decoration: const InputDecoration(
                      labelText: 'Folder (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tagsController,
                    decoration: const InputDecoration(
                      labelText: 'Tags (comma separated)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<SessionMode>(
                    initialValue: mode,
                    items: SessionMode.values
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(_modeLabelShort(m)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setSheetState(() => mode = value);
                      updateValidation(
                        setSheetState,
                        showQuestion: value == SessionMode.learn ||
                            value == SessionMode.speedTest,
                        showTime: value == SessionMode.speedTest ||
                            value == SessionMode.drillHard,
                        showNew: value == SessionMode.review,
                      );
                    },
                    decoration: const InputDecoration(labelText: 'Mode'),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: isGlobal,
                    title: const Text('Share across exercises'),
                    subtitle: const Text('Make this template available everywhere'),
                    onChanged: (value) {
                      setSheetState(() => isGlobal = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  if (showQuestion)
                    TextField(
                      controller: questionController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Question count',
                        errorText: questionError,
                      ),
                      onChanged: (_) => updateValidation(
                        setSheetState,
                        showQuestion: showQuestion,
                        showTime: showTime,
                        showNew: showNew,
                      ),
                    ),
                  if (showTime) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: timeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Time limit (minutes)',
                        errorText: timeError,
                      ),
                      onChanged: (_) => updateValidation(
                        setSheetState,
                        showQuestion: showQuestion,
                        showTime: showTime,
                        showNew: showNew,
                      ),
                    ),
                  ],
                  if (showNew) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: newCardController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'New cards (optional)',
                        errorText: newCardError,
                      ),
                      onChanged: (_) => updateValidation(
                        setSheetState,
                        showQuestion: showQuestion,
                        showTime: showTime,
                        showNew: showNew,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: canSave ? () => saveTemplate(setSheetState) : null,
                    child: const Text('Save Template'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _modeLabelShort(SessionMode mode) {
    return switch (mode) {
      SessionMode.review => 'Review',
      SessionMode.practiceLearned => 'Practice Learned',
      SessionMode.learn => 'Learn',
      SessionMode.speedTest => 'Speed Test',
      SessionMode.drillHard => 'Drill Hard',
    };
  }

  List<_SessionTemplate> _builtinTemplates() {
    return const [
      _SessionTemplate(
        key: 'builtin:learn10',
        title: 'Learn 10',
        subtitle: 'Flashcards, no scoring',
        mode: SessionMode.learn,
        questionCount: 10,
      ),
      _SessionTemplate(
        key: 'builtin:speed10',
        title: 'Speed Test 10',
        subtitle: '2 min timed drill',
        mode: SessionMode.speedTest,
        questionCount: 10,
        timeLimitSeconds: 120,
      ),
      _SessionTemplate(
        key: 'builtin:practice-learned',
        title: 'Practice Learned',
        subtitle: 'Review learned items',
        mode: SessionMode.practiceLearned,
      ),
      _SessionTemplate(
        key: 'builtin:drill-hard',
        title: 'Drill Hard',
        subtitle: '2 min hard items',
        mode: SessionMode.drillHard,
        timeLimitSeconds: 120,
      ),
      _SessionTemplate(
        key: 'builtin:review-5-new',
        title: 'Review 5 New',
        subtitle: 'Introduce new cards',
        mode: SessionMode.review,
        newCardCount: 5,
      ),
    ];
  }
}

class _SessionTemplate {
  final String key;
  final String title;
  final String subtitle;
  final SessionMode mode;
  final int? questionCount;
  final int? timeLimitSeconds;
  final int? newCardCount;

  const _SessionTemplate({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.mode,
    this.questionCount,
    this.timeLimitSeconds,
    this.newCardCount,
  });
}

class _ModeCta extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ModeCta({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final bg = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: enabled ? bg : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: theme.colorScheme.primary, width: 2)
              : Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: enabled ? fg : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: enabled
                    ? (selected
                        ? theme.colorScheme.onPrimary.withValues(alpha: 0.9)
                        : theme.colorScheme.onSurfaceVariant)
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ModeTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: enabled
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
      trailing: selected
          ? Icon(Icons.radio_button_checked, color: theme.colorScheme.primary)
          : Icon(Icons.radio_button_unchecked,
              color: theme.colorScheme.onSurfaceVariant),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }
}
