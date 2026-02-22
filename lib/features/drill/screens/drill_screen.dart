import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/answer_input/answer_feedback_banner.dart';
import '../../../core/answer_input/answer_input_controller.dart';
import '../../../core/answer_input/answer_input_mode.dart';
import '../../../core/answer_input/multiple_choice_answers.dart';
import '../../../core/audio/audio_provider.dart';
import '../../../core/music/pitch_class.dart';
import '../../../core/widgets/notation/simple_sheet_music_adapter.dart';
import '../../../core/widgets/piano_input/flutter_piano_pro_adapter.dart';
import '../providers/drill_provider.dart';
import '../widgets/audio_play_button.dart';

class DrillScreen extends ConsumerStatefulWidget {
  final String exerciseId;
  final Set<String>? selectedGroups;
  final int questionCount;
  final bool hardOnly;

  const DrillScreen({
    required this.exerciseId,
    this.selectedGroups,
    this.questionCount = 10,
    this.hardOnly = false,
    super.key,
  });

  @override
  ConsumerState<DrillScreen> createState() => _DrillScreenState();
}

class _DrillScreenState extends ConsumerState<DrillScreen> {
  Timer? _timer;
  int _remainingSeconds = 0;
  final _answerController = TextEditingController();
  AnswerInputMode _inputMode = AnswerInputMode.keyboard;
  AnswerInputController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startDrill();
    });
  }

  void _startDrill() async {
    final db = ref.read(appDatabaseProvider);
    final settings = await db.settingsDao.getSettings();
    final exercise =
        await ref.read(exerciseByIdProvider(widget.exerciseId).future);
    final timeLimit = settings?.drillTimeLimitSeconds ?? 120;

    if (widget.hardOnly) {
      await ref
          .read(drillSessionProvider(widget.exerciseId).notifier)
          .startHardDrillSession(
            exercise: exercise,
            selectedGroups: widget.selectedGroups,
            timeLimitSeconds: timeLimit,
          );
    } else {
      await ref
          .read(drillSessionProvider(widget.exerciseId).notifier)
          .startDrill(
            totalQuestions: widget.questionCount,
            timeLimitSeconds: timeLimit,
            exercise: exercise,
            selectedGroups: widget.selectedGroups,
          );
    }

    if (!mounted) return;
    setState(() {
      _inputMode = AnswerInputModeX.fromSettingsString(
          settings?.answerInputMode ?? 'keyboard');
    });
    _remainingSeconds = timeLimit;
    _startTimer();
    _createController();
  }

  void _createController() {
    final drillState = ref.read(drillSessionProvider(widget.exerciseId));
    final question = drillState.currentQuestion;
    if (question == null) return;

    _controller?.dispose();

    var mode = _inputMode;
    if (mode == AnswerInputMode.multipleChoice &&
        question.multipleChoiceOptions == null) {
      mode = AnswerInputMode.selfReveal;
    }

    _controller = AnswerInputController(
      mode: mode,
      expectedAnswer: question.expectedAnswer,
      answerText: question.answerText,
      multipleChoiceOptions: question.multipleChoiceOptions,
      onResult: (correct) {
        ref
            .read(drillSessionProvider(widget.exerciseId).notifier)
            .submitAnswer(correct: correct);
        setState(() {});
      },
    );
    setState(() {});
  }

  void _nextQuestion() {
    ref
        .read(drillSessionProvider(widget.exerciseId).notifier)
        .nextQuestion();
    _createController();
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
    _controller?.dispose();
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
          data: (exercise) => Text(
              widget.hardOnly ? 'Drill Hard' : exercise.title),
          loading: () => const Text('Loading...'),
          error: (_, _) => Text(widget.hardOnly ? 'Drill Hard' : 'Drill'),
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
      _timer?.cancel();
      return _buildCompleteSummary(context, drillState);
    }

    final question = drillState.currentQuestion;
    final ctrl = _controller;
    final useKeyboard = ctrl?.mode == AnswerInputMode.keyboard;
    final useMcq = ctrl?.mode == AnswerInputMode.multipleChoice;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: drillState.progress,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 8),
          Text(
            'Question ${drillState.currentQuestionIndex + 1} of ${drillState.totalQuestions}',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

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
          const SizedBox(height: 24),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                question?.promptText ?? 'Loading...',
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (question?.audioData != null) ...[
            AudioPlayButton(
              audioData: question!.audioData!,
              audioService: ref.watch(audioServiceProvider),
            ),
            const SizedBox(height: 16),
          ],

          // For non-MCQ/non-keyboard: show notation before answering
          if (!useMcq && !useKeyboard && question?.notationData != null) ...[
            SimpleSheetMusicAdapter(
              data: question!.notationData!,
              height: 120,
            ),
            const SizedBox(height: 16),
          ],

          if (ctrl != null) ...[
            // --- Multiple choice mode ---
            if (useMcq) _buildMcqSection(ctrl, question),

            // --- Keyboard mode ---
            if (useKeyboard) _buildKeyboardSection(ctrl, question),
          ],

          // --- Text input fallback ---
          if (!useMcq && !useKeyboard) ...[
            TextField(
              controller: _answerController,
              decoration: const InputDecoration(
                hintText: 'Type your answer...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submitAnswer(),
            ),
            const SizedBox(height: 16),
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
        ],
      ),
    );
  }

  Widget _buildMcqSection(AnswerInputController ctrl, dynamic question) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        if (ctrl.phase == AnswerPhase.input) {
          return MultipleChoiceAnswers(
            options: ctrl.multipleChoiceOptions!,
            correctAnswer: ctrl.expectedAnswer.toString(),
            showResult: false,
            disabled: false,
            onSelected: ctrl.selectMcqAnswer,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MultipleChoiceAnswers(
              options: ctrl.multipleChoiceOptions!,
              correctAnswer: ctrl.expectedAnswer.toString(),
              selectedAnswer: ctrl.selectedMcqAnswer,
              showResult: true,
              disabled: true,
            ),
            if (question?.notationData != null) ...[
              const SizedBox(height: 12),
              SimpleSheetMusicAdapter(
                data: question!.notationData!,
                height: 120,
              ),
            ],
            const SizedBox(height: 12),
            AnswerFeedbackBanner(
              isCorrect: ctrl.result!,
              answerText: ctrl.displayAnswer,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _nextQuestion,
              child: const Text('Next Question'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKeyboardSection(AnswerInputController ctrl, dynamic question) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: FlutterPianoProAdapter(
                octaveCount: 2,
                startOctave: 4,
                highlightedNotes: ctrl.keyboardSubmitted
                    ? ctrl.expectedPitchClasses
                    : const <PitchClass>{},
                onNotesChanged: ctrl.keyboardSubmitted
                    ? null
                    : ctrl.updateKeyboardNotes,
              ),
            ),
            if (ctrl.isMultiNote && ctrl.phase == AnswerPhase.input) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed:
                    ctrl.canSubmitKeyboard ? ctrl.submitKeyboard : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: const Text('Submit'),
              ),
            ],
            if (ctrl.keyboardSubmitted) ...[
              const SizedBox(height: 12),
              if (question?.notationData != null) ...[
                SimpleSheetMusicAdapter(
                  data: question!.notationData!,
                  height: 120,
                ),
                const SizedBox(height: 12),
              ],
              AnswerFeedbackBanner(
                isCorrect: ctrl.result!,
                answerText: ctrl.displayAnswer,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _nextQuestion,
                child: const Text('Next Question'),
              ),
            ],
          ],
        );
      },
    );
  }

  void _submitAnswer() {
    final drillState = ref.read(drillSessionProvider(widget.exerciseId));
    final question = drillState.currentQuestion;
    final userAnswer = _answerController.text.trim();
    final expected = question?.expectedAnswer?.toString().trim() ?? '';
    final correct = userAnswer.isNotEmpty &&
        userAnswer.toLowerCase() == expected.toLowerCase();
    ref
        .read(drillSessionProvider(widget.exerciseId).notifier)
        .submitAnswer(correct: correct);
  }

  Widget _buildCompleteSummary(
    BuildContext context,
    DrillSessionState drillState,
  ) {
    final theme = Theme.of(context);
    final isEmpty = drillState.totalQuestions == 0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isEmpty ? Icons.check_circle : Icons.emoji_events,
              size: 80,
              color: isEmpty ? Colors.green : theme.colorScheme.secondary,
            ),
            const SizedBox(height: 24),
            Text(
              isEmpty
                  ? 'No hard items found'
                  : widget.hardOnly
                      ? 'Drill Hard Complete!'
                      : 'Drill Complete!',
              style: theme.textTheme.headlineLarge,
            ),
            const SizedBox(height: 16),
            Text(
              isEmpty
                  ? 'Nothing to drill right now.'
                  : '${drillState.correctCount} / ${drillState.totalQuestions} correct',
              style: theme.textTheme.headlineSmall,
            ),
            if (!isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Score: ${drillState.score}%',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
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
