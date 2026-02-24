import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../content/providers/content_providers.dart';
import '../../../database/app_database.dart';
import '../../practice/providers/exercise_counts_provider.dart';
import '../providers/deck_review_provider.dart';
import '../screens/deck_review_screen.dart';
import '../../srs/providers/srs_provider.dart';
import '../../streak/providers/streak_provider.dart';
import '../../today/providers/today_session_provider.dart';

Future<void> showDeckSessionSheet({
  required BuildContext context,
  required WidgetRef ref,
  required AppDatabase db,
  required DeckTreeNode node,
  required List<String> deckIds,
}) async {
  final settings = await db.settingsDao.getSettings();
  if (!context.mounted) return;

  final newCardsPerDay = settings?.newCardsPerDay ?? 5;
  final maxNewAllowed = newCardsPerDay > 20 ? newCardsPerDay : 20;
  final maxNew = node.newCards.clamp(0, maxNewAllowed);
  final defaultNew = maxNew == 0 ? 0 : maxNew;
  final defaultDrillCount = settings?.deckDrillCount ?? 10;
  final hardnessLevel = settings?.deckHardnessLevel ?? 'medium';

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return _DeckSessionSheet(
        db: db,
        ref: ref,
        node: node,
        deckIds: deckIds,
        maxNew: maxNew,
        defaultNew: defaultNew,
        defaultDrillCount: defaultDrillCount,
        hardnessLevel: hardnessLevel,
      );
    },
  );
}

enum _DeckSessionMode { review, drill }

enum _DrillMode { random, hard }

class _DeckSessionSheet extends StatefulWidget {
  final AppDatabase db;
  final WidgetRef ref;
  final DeckTreeNode node;
  final List<String> deckIds;
  final int maxNew;
  final int defaultNew;
  final int defaultDrillCount;
  final String hardnessLevel;

  const _DeckSessionSheet({
    required this.db,
    required this.ref,
    required this.node,
    required this.deckIds,
    required this.maxNew,
    required this.defaultNew,
    required this.defaultDrillCount,
    required this.hardnessLevel,
  });

  @override
  State<_DeckSessionSheet> createState() => _DeckSessionSheetState();
}

class _DeckSessionSheetState extends State<_DeckSessionSheet> {
  _DeckSessionMode _mode = _DeckSessionMode.review;
  _DrillMode _drillMode = _DrillMode.random;
  late int _newCount = widget.defaultNew;
  late int _drillCount = widget.defaultDrillCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final due = widget.node.dueCards;
    final learned = widget.node.learnedCards;
    final total = widget.node.totalCards;

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
            widget.node.deck.title,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '$due due · $learned learned · $total cards',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _buildModeToggle(theme),
          const SizedBox(height: 16),
          if (_mode == _DeckSessionMode.review)
            _buildReviewOptions(theme)
          else
            _buildDrillOptions(theme),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _canStartReview(due)
                ? () => _startSession(context)
                : null,
            child: Text(_mode == _DeckSessionMode.review
                ? 'Start Review'
                : 'Start Drill'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(height: 8),
          const Divider(),
          TextButton(
            onPressed: _toggleDailyReviewInclusion,
            child: Text(
              widget.node.deck.excludeFromDailyReview
                  ? 'Add To Daily Review (incl. subdecks)'
                  : 'Remove From Daily Review (incl. subdecks)',
            ),
          ),
          TextButton(
            onPressed: _confirmResetDeckProgress,
            child: const Text('Reset Deck Progress (cards only)'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleDailyReviewInclusion() async {
    final repo = widget.ref.read(contentRepositoryProvider);
    await repo.setDeckExcludedFromDailyReview(
      widget.node.deck.id,
      !widget.node.deck.excludeFromDailyReview,
      includeSubdecks: true,
    );
    _invalidateCounts();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _confirmResetDeckProgress() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset deck progress?'),
        content: Text(
          'Reset SRS progress for cards in "${widget.node.deck.title}"'
          '${widget.node.children.isNotEmpty ? ' and its subdecks' : ''}? '
          'This resets card review history and scheduling for those cards only.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final repo = widget.ref.read(contentRepositoryProvider);
    await repo.resetDeckCardProgress(widget.node.deck.id, includeSubdecks: true);
    _invalidateCounts(includeStreak: true);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _invalidateCounts({bool includeStreak = false}) {
    widget.ref.invalidate(deckTreeStatsProvider);
    widget.ref.invalidate(conceptDeckStatsProvider);
    widget.ref.invalidate(todaySessionProvider);
    widget.ref.invalidate(todayDashboardCountsProvider);
    widget.ref.invalidate(todayCategoryDashboardCountsProvider(TodayReviewCategory.learning));
    widget.ref.invalidate(todayCategoryDashboardCountsProvider(TodayReviewCategory.ear));
    widget.ref.invalidate(dueCardIdsProvider);
    widget.ref.invalidate(dueCardCountProvider);
    widget.ref.invalidate(exerciseCountsProvider);
    if (includeStreak) {
      widget.ref.invalidate(todayStreakProvider);
    }
  }

  Widget _buildModeToggle(ThemeData theme) {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Review'),
          selected: _mode == _DeckSessionMode.review,
          onSelected: (_) => setState(() => _mode = _DeckSessionMode.review),
        ),
        ChoiceChip(
          label: const Text('Drill'),
          selected: _mode == _DeckSessionMode.drill,
          onSelected: (_) => setState(() => _mode = _DeckSessionMode.drill),
        ),
      ],
    );
  }

  Widget _buildReviewOptions(ThemeData theme) {
    final due = widget.node.dueCards;
    final maxNew = widget.maxNew;
    final hasNew = maxNew > 0;

    if (due > 0) {
      return Text(
        'Review due cards. New cards are only added if your global daily budget has remaining slots.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    if (!hasNew) {
      return Text(
        'No due cards and no global new-card slots remaining today.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('New cards to add', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _newCount.toDouble(),
                min: 0,
                max: maxNew.toDouble(),
                divisions: maxNew == 0 ? 1 : maxNew,
                label: '$_newCount',
                onChanged: (value) {
                  setState(() => _newCount = value.round());
                },
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                '$_newCount',
                textAlign: TextAlign.end,
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
        Text(
          'Max today: $maxNew',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildDrillOptions(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Drill mode', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Random'),
              selected: _drillMode == _DrillMode.random,
              onSelected: (_) => setState(() => _drillMode = _DrillMode.random),
            ),
            ChoiceChip(
              label: const Text('Hard'),
              selected: _drillMode == _DrillMode.hard,
              onSelected: (_) => setState(() => _drillMode = _DrillMode.hard),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Card count', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              onPressed: _drillCount > 5
                  ? () => setState(() => _drillCount -= 5)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            Text('$_drillCount', style: theme.textTheme.titleMedium),
            IconButton(
              onPressed: () => setState(() => _drillCount += 5),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _drillMode == _DrillMode.hard
              ? 'Hardness: ${_hardnessLabel(widget.hardnessLevel)} (edit in Settings)'
              : 'Random sample from this deck',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  bool _canStartReview(int due) {
    if (_mode == _DeckSessionMode.drill) return true;
    if (due > 0) return true;
    return widget.maxNew > 0 && _newCount > 0;
  }

  Future<void> _startSession(BuildContext context) async {
    if (_mode == _DeckSessionMode.review) {
      final due = widget.node.dueCards;
      final count = due + (due == 0 ? _newCount : widget.maxNew);
      Navigator.of(context).pop();
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => DeckReviewScreen(
            deckIds: widget.deckIds,
            questionCount: count,
            newCardCount: due == 0 ? _newCount : null,
          ),
        ),
      );
      return;
    }

    await widget.db.settingsDao.upsertSettings(
      SettingsCompanion(deckDrillCount: Value(_drillCount)),
    );

    if (_drillMode == _DrillMode.random) {
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => DeckReviewScreen(
            deckIds: widget.deckIds,
            questionCount: _drillCount,
            isRandom: true,
            modeLabel: 'Drill',
          ),
        ),
      );
      return;
    }

    final threshold = _stabilityThreshold(widget.hardnessLevel);
    final cards = await widget.db.cardsDao.getHardCardsForDecks(
      widget.deckIds,
      threshold,
      _drillCount,
    );
    final ids = cards.map((c) => c.id).toList();
    if (!mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => DeckReviewScreen(
          deckIds: widget.deckIds,
          questionCount: ids.length,
          isRandom: true,
          cardIdsOverride: ids,
          modeLabel: 'Drill (Hard)',
        ),
      ),
    );
  }

  String _hardnessLabel(String value) {
    return switch (value) {
      'strict' => 'Strict',
      'wide' => 'Wide',
      _ => 'Medium',
    };
  }

  double _stabilityThreshold(String value) {
    return switch (value) {
      'strict' => 2.0,
      'wide' => 5.0,
      _ => 3.5,
    };
  }
}
