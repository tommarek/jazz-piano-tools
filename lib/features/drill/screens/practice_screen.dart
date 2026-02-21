import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/drill_provider.dart';

class PracticeScreen extends ConsumerStatefulWidget {
  final String exerciseId;

  const PracticeScreen({required this.exerciseId, super.key});

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  bool _showAnswer = false;
  int _currentQuestion = 0;
  final int _totalQuestions = 10;
  int _correctCount = 0;
  bool _isComplete = false;

  void _revealAnswer() {
    setState(() {
      _showAnswer = true;
    });
  }

  void _markAnswer(bool correct) {
    setState(() {
      if (correct) _correctCount++;
      _currentQuestion++;
      _showAnswer = false;

      if (_currentQuestion >= _totalQuestions) {
        _isComplete = true;
      }
    });
  }

  double get _progress =>
      _totalQuestions > 0 ? _currentQuestion / _totalQuestions : 0.0;

  @override
  Widget build(BuildContext context) {
    final exerciseAsync = ref.watch(exerciseByIdProvider(widget.exerciseId));

    return Scaffold(
      appBar: AppBar(
        title: exerciseAsync.when(
          data: (exercise) => Text(exercise.title),
          loading: () => const Text('Loading...'),
          error: (_, _) => const Text('Practice'),
        ),
      ),
      body: exerciseAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (exercise) {
          if (_isComplete) {
            return _buildCompleteSummary(context);
          }
          return _buildPracticeBody(context);
        },
      ),
    );
  }

  Widget _buildPracticeBody(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress bar
          LinearProgressIndicator(
            value: _progress,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 8),
          Text(
            'Question ${_currentQuestion + 1} of $_totalQuestions',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Prompt card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Identify the chord or interval',
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Answer area
          if (_showAnswer) ...[
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      'Answer',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'C Major 7',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'How did you do?',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _markAnswer(false),
                    icon: const Icon(Icons.close),
                    label: const Text('Incorrect'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _markAnswer(true),
                    icon: const Icon(Icons.check),
                    label: const Text('Correct'),
                  ),
                ),
              ],
            ),
          ],

          const Spacer(),

          // Show answer button
          if (!_showAnswer)
            FilledButton.tonal(
              onPressed: _revealAnswer,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              child: const Text('Show Answer'),
            ),
        ],
      ),
    );
  }

  Widget _buildCompleteSummary(BuildContext context) {
    final theme = Theme.of(context);
    final score =
        _totalQuestions > 0
            ? ((_correctCount / _totalQuestions) * 100).round()
            : 0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.emoji_events,
              size: 80,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(height: 24),
            Text('Practice Complete!', style: theme.textTheme.headlineLarge),
            const SizedBox(height: 16),
            Text(
              '$_correctCount / $_totalQuestions correct',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Score: $score%',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
