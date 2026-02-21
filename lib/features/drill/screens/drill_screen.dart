import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/drill_provider.dart';

class DrillScreen extends ConsumerStatefulWidget {
  final String exerciseId;

  const DrillScreen({required this.exerciseId, super.key});

  @override
  ConsumerState<DrillScreen> createState() => _DrillScreenState();
}

class _DrillScreenState extends ConsumerState<DrillScreen> {
  Timer? _timer;
  int _remainingSeconds = 0;
  final _answerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startDrill();
    });
  }

  void _startDrill() {
    const timeLimit = 120;
    ref.read(drillSessionProvider(widget.exerciseId).notifier).startDrill(
      totalQuestions: 10,
      timeLimitSeconds: timeLimit,
    );
    _remainingSeconds = timeLimit;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        timer.cancel();
        return;
      }
      setState(() {
        _remainingSeconds--;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _answerController.dispose();
    super.dispose();
  }

  String get _formattedTime {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final exerciseAsync = ref.watch(exerciseByIdProvider(widget.exerciseId));
    final drillState = ref.watch(drillSessionProvider(widget.exerciseId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: exerciseAsync.when(
          data: (exercise) => Text(exercise.title),
          loading: () => const Text('Loading...'),
          error: (_, _) => const Text('Drill'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                _formattedTime,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontFeatures: [const FontFeature.tabularFigures()],
                  color: _remainingSeconds < 30
                      ? theme.colorScheme.error
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
      body: exerciseAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (exercise) => _buildDrillBody(context, drillState),
      ),
    );
  }

  Widget _buildDrillBody(BuildContext context, DrillSessionState drillState) {
    final theme = Theme.of(context);

    if (drillState.phase == DrillPhase.complete) {
      return _buildCompleteSummary(context, drillState);
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress bar
          LinearProgressIndicator(
            value: drillState.progress,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 8),
          Text(
            'Question ${drillState.currentQuestion + 1} of ${drillState.totalQuestions}',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Score
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.stars, color: theme.colorScheme.secondary),
              const SizedBox(width: 8),
              Text(
                'Score: ${drillState.score}%',
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Prompt
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

          // Feedback banner
          if (drillState.lastAnswerCorrect != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: drillState.lastAnswerCorrect!
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: drillState.lastAnswerCorrect!
                      ? Colors.green
                      : Colors.red,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    drillState.lastAnswerCorrect!
                        ? Icons.check_circle
                        : Icons.cancel,
                    color: drillState.lastAnswerCorrect!
                        ? Colors.green
                        : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    drillState.lastAnswerCorrect! ? 'Correct!' : 'Incorrect',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: drillState.lastAnswerCorrect!
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                ],
              ),
            ),

          const Spacer(),

          // Answer input area (placeholder)
          TextField(
            controller: _answerController,
            decoration: const InputDecoration(
              hintText: 'Type your answer...',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submitAnswer(),
          ),
          const SizedBox(height: 16),

          // Submit / Next button
          if (drillState.phase == DrillPhase.feedback)
            FilledButton(
              onPressed: () {
                _answerController.clear();
                ref
                    .read(drillSessionProvider(widget.exerciseId).notifier)
                    .nextQuestion();
              },
              child: const Text('Next Question'),
            )
          else
            FilledButton(
              onPressed: _submitAnswer,
              child: const Text('Submit'),
            ),
        ],
      ),
    );
  }

  void _submitAnswer() {
    // Placeholder: always mark as correct if non-empty
    final correct = _answerController.text.trim().isNotEmpty;
    ref
        .read(drillSessionProvider(widget.exerciseId).notifier)
        .submitAnswer(correct: correct);
  }

  Widget _buildCompleteSummary(
    BuildContext context,
    DrillSessionState drillState,
  ) {
    final theme = Theme.of(context);

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
            Text('Drill Complete!', style: theme.textTheme.headlineLarge),
            const SizedBox(height: 16),
            Text(
              '${drillState.correctCount} / ${drillState.totalQuestions} correct',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Score: ${drillState.score}%',
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
