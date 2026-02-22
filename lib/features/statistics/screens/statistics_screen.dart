import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../statistics_service.dart';

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    final statsService = StatisticsService(db);

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Intervals'),
                Tab(text: 'Chords'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _TopicStats(
                    topic: 'intervals',
                    statsService: statsService,
                  ),
                  _TopicStats(
                    topic: 'chords',
                    statsService: statsService,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicStats extends StatefulWidget {
  final String topic;
  final StatisticsService statsService;

  const _TopicStats({required this.topic, required this.statsService});

  @override
  State<_TopicStats> createState() => _TopicStatsState();
}

class _TopicStatsState extends State<_TopicStats> {
  Map<String, ItemStats>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final stats = await widget.statsService.getItemStats(widget.topic);
    if (mounted) {
      setState(() {
        _stats = stats;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_stats == null || _stats!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No data yet',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete some exercises to see your stats',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final sorted = _stats!.values.toList()
      ..sort((a, b) => a.accuracy.compareTo(b.accuracy));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final item = sorted[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.itemId, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: item.accuracy,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        color: _accuracyColor(item.accuracy),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${(item.accuracy * 100).round()}%',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: _accuracyColor(item.accuracy),
                      ),
                    ),
                    Text(
                      '${item.totalAttempts} attempts',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _accuracyColor(double accuracy) {
    if (accuracy >= 0.80) return Colors.green;
    if (accuracy >= 0.60) return Colors.orange;
    return Colors.red;
  }
}
