import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/answer_input/answer_input_controller.dart';
import '../../../core/answer_input/answer_input_mode.dart';
import '../../../core/answer_input/multiple_choice_answers.dart';
import '../../../core/audio/audio_provider.dart';
import '../../../core/widgets/notation/simple_sheet_music_adapter.dart';
import '../providers/drill_provider.dart';
import '../widgets/audio_play_button.dart';
import '../widgets/session_app_bar_title.dart';

/// Learn mode screen — flashcard-style, no scoring.
class ExerciseLearnScreen extends ConsumerStatefulWidget {
  final String exerciseId;
  final Set<String>? selectedGroups;
  final int questionCount;

  const ExerciseLearnScreen({
    required this.exerciseId,
    this.selectedGroups,
    this.questionCount = 10,
    super.key,
  });

  @override
  ConsumerState<ExerciseLearnScreen> createState() =>
      _ExerciseLearnScreenState();
}

class _ExerciseLearnScreenState extends ConsumerState<ExerciseLearnScreen> {
  bool _started = false;
  int _studyAgainCount = 0;
  AnswerInputController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startLearn();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _startLearn() async {
    final exercise =
        await ref.read(exerciseByIdProvider(widget.exerciseId).future);
    await ref.read(drillSessionProvider(widget.exerciseId).notifier).startDrill(
      totalQuestions: widget.questionCount,
      timeLimitSeconds: 0,
      exercise: exercise,
      selectedGroups: widget.selectedGroups,
    );
    if (!mounted) return;
    setState(() {
      _started = true;
    });
    _createController();
  }

  void _createController() {
    final drillState = ref.read(drillSessionProvider(widget.exerciseId));
    final question = drillState.currentQuestion;
    if (question == null) return;

    _controller?.dispose();

    final isMcq = question.multipleChoiceOptions != null;
    _controller = AnswerInputController(
      mode: isMcq ? AnswerInputMode.multipleChoice : AnswerInputMode.selfReveal,
      expectedAnswer: question.expectedAnswer,
      answerText: question.answerText,
      multipleChoiceOptions: question.multipleChoiceOptions,
      onResult: (_) => setState(() {}),
    );
    setState(() {});
  }

  void _revealAnswer() {
    _controller?.revealAnswer();
    setState(() {});
  }

  void _studyAgain() {
    ref
        .read(drillSessionProvider(widget.exerciseId).notifier)
        .repeatCurrentQuestion();
    _studyAgainCount++;
    // Record as incorrect for SRS so it comes back sooner
    _advance(correct: false);
  }

  void _next() {
    _advance(correct: true);
  }

  void _advance({required bool correct}) async {
    await ref
        .read(drillSessionProvider(widget.exerciseId).notifier)
        .submitAnswer(correct: correct);
    if (!mounted) return;
    ref
        .read(drillSessionProvider(widget.exerciseId).notifier)
        .nextQuestion();
    _createController();
  }

  Future<void> _showExitConfirmation() async {
    final drillState = ref.read(drillSessionProvider(widget.exerciseId));
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End study session?'),
        content: Text(
          'You have studied ${drillState.currentQuestionIndex} of '
          '${drillState.totalQuestions} items.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continue'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End Session'),
          ),
        ],
      ),
    );

    if (shouldExit == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final exerciseAsync = ref.watch(exerciseByIdProvider(widget.exerciseId));
    final drillState = ref.watch(drillSessionProvider(widget.exerciseId));

    return PopScope(
      canPop: !_started || drillState.phase == DrillPhase.complete,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showExitConfirmation();
      },
      child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: SessionAppBarTitle(
          title: 'Learn',
          subtitleParts: [
            '${drillState.currentQuestionIndex + 1}/${drillState.totalQuestions}',
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              if (_started && drillState.phase != DrillPhase.complete) {
                _showExitConfirmation();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: exerciseAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (exercise) {
          if (!_started) {
            return const Center(child: CircularProgressIndicator());
          }
          if (drillState.phase == DrillPhase.complete) {
            return _buildComplete(context, drillState);
          }
          return _buildLearnBody(context, drillState);
        },
      ),
    ),
    );
  }

  Widget _buildLearnBody(BuildContext context, DrillSessionState drillState) {
    final theme = Theme.of(context);
    final question = drillState.currentQuestion;
    final ctrl = _controller;
    final isAnswerShown = ctrl?.phase == AnswerPhase.feedback;
    final isMcqMode = ctrl?.mode == AnswerInputMode.multipleChoice;

    return Column(
      children: [
        // Progress
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Column(
            children: [
              LinearProgressIndicator(
                value: drillState.progress,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
        ),

        // Card content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: (!isAnswerShown && !isMcqMode) ? _revealAnswer : null,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Prompt
                      Text(
                        question?.promptText ?? 'Loading...',
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),

                      // Audio play button
                      if (question?.audioData != null) ...[
                        const SizedBox(height: 16),
                        AudioPlayButton(
                          audioData: question!.audioData!,
                          audioService: ref.watch(audioServiceProvider),
                        ),
                      ],

                      // MCQ options
                      if (isMcqMode && ctrl != null) ...[
                        const SizedBox(height: 24),
                        ListenableBuilder(
                          listenable: ctrl,
                          builder: (context, _) {
                            if (ctrl.phase == AnswerPhase.input) {
                              return MultipleChoiceAnswers(
                                options: ctrl.multipleChoiceOptions!,
                                correctAnswer: ctrl.expectedAnswer.toString(),
                                showResult: false,
                                disabled: false,
                                onSelected: (option) {
                                  ctrl.selectMcqAnswer(option);
                                },
                              );
                            }
                            return MultipleChoiceAnswers(
                              options: ctrl.multipleChoiceOptions!,
                              correctAnswer: ctrl.expectedAnswer.toString(),
                              selectedAnswer: ctrl.selectedMcqAnswer,
                              showResult: true,
                              disabled: true,
                            );
                          },
                        ),
                      ],

                      // Answer section (revealed)
                      if (isAnswerShown) ...[
                        const SizedBox(height: 16),
                        Divider(
                          color: theme.colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 16),

                        // Answer text (for non-MCQ)
                        if (!isMcqMode && ctrl != null) ...[
                          Text(
                            ctrl.displayAnswer,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],

                        // Notation (shown after reveal)
                        if (question?.notationData != null) ...[
                          const SizedBox(height: 16),
                          SimpleSheetMusicAdapter(
                            data: question!.notationData!,
                            height: 120,
                          ),
                        ],
                      ],

                      // Tap hint (non-MCQ, answer hidden)
                      if (!isAnswerShown && !isMcqMode) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Tap to reveal answer',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // Bottom buttons
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: isAnswerShown
                ? Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _studyAgain,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('Study Again'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton(
                          onPressed: _next,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('Next'),
                        ),
                      ),
                    ],
                  )
                : isMcqMode
                    ? const SizedBox.shrink()
                    : FilledButton.tonal(
                        onPressed: _revealAnswer,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: const Text('Show Answer'),
                      ),
          ),
        ),
      ],
    );
  }

  Widget _buildComplete(BuildContext context, DrillSessionState drillState) {
    final theme = Theme.of(context);
    final totalStudied = drillState.totalQuestions;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.school,
              size: 80,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text('Study Complete!', style: theme.textTheme.headlineLarge),
            const SizedBox(height: 16),
            Text(
              'You studied $totalStudied items',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_studyAgainCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '$_studyAgainCount reviewed again',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Keep it up!',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.primary,
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
