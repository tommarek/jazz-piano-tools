import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/answer_input/answer_action_bar.dart';
import '../../../core/answer_input/answer_input_area.dart';
import '../../../core/answer_input/answer_input_controller.dart';
import '../../../core/answer_input/answer_input_mode.dart';
import '../../../core/answer_input/duration_formatter.dart';
import '../../../core/answer_input/rating_buttons.dart';
import '../../../core/audio/audio_provider.dart';
import '../../../core/constants/ui_timing.dart';
import '../../../core/widgets/notation/simple_sheet_music_adapter.dart';
import '../../../domain/models/srs_card_state.dart';
import '../../library/providers/library_provider.dart';
import '../../srs/providers/srs_provider.dart';
import '../providers/drill_provider.dart';
import 'drill_screen.dart';
import 'learn_screen.dart';
import '../widgets/audio_play_button.dart';
import '../widgets/session_app_bar_title.dart';

class PracticeScreen extends ConsumerStatefulWidget {
  final String exerciseId;
  final Set<String>? selectedGroups;
  final int? newCardCount;
  final bool learnedOnly;

  const PracticeScreen({
    required this.exerciseId,
    this.selectedGroups,
    this.newCardCount,
    this.learnedOnly = false,
    super.key,
  });

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  bool _started = false;
  bool _showIntervalHints = true;
  SrsCardState? _currentItemState;
  AnswerInputController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startPractice(newCardCount: widget.newCardCount);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _startPractice({bool ignoreNewCardLimit = false, int? newCardCount}) async {
    final db = ref.read(appDatabaseProvider);
    final settings = await db.settingsDao.getSettings();
    final exercise =
        await ref.read(exerciseByIdProvider(widget.exerciseId).future);
    final count = await ref
        .read(drillSessionProvider(widget.exerciseId).notifier)
        .startPracticeSession(
          exercise: exercise,
          selectedGroups: widget.selectedGroups,
          ignoreNewCardLimit: ignoreNewCardLimit,
          newCardCount: newCardCount,
          learnedOnly: widget.learnedOnly,
        );
    if (!mounted) return;
    setState(() {
      _started = true;
      _showIntervalHints = settings?.showIntervalHints ?? true;
    });
    if (count > 0) {
      _loadItemState();
      _createController();
    }
  }

  void _createController() {
    final drillState = ref.read(drillSessionProvider(widget.exerciseId));
    final question = drillState.currentQuestion;
    if (question == null) return;

    _controller?.dispose();

    _controller = AnswerInputController(
      mode: AnswerInputMode.keyboard,
      expectedAnswer: question.expectedAnswer,
      answerText: question.answerText,
      onResult: (correct) {
        setState(() {});
        if (!correct) {
          Future.delayed(kAutoRevealAgainDelay, () {
            if (mounted) _rateAndAdvance(0);
          });
        }
      },
    );
    setState(() {});
  }

  Future<void> _loadItemState() async {
    final drillState = ref.read(drillSessionProvider(widget.exerciseId));
    final question = drillState.currentQuestion;
    if (question == null) {
      setState(() => _currentItemState = null);
      return;
    }

    final meta = question.metadata;
    final topic = meta['topic'] as String?;
    final itemId = meta['itemId'] as String?;
    if (topic == null || itemId == null) {
      setState(() => _currentItemState = null);
      return;
    }

    final db = ref.read(appDatabaseProvider);
    final existing = await db.itemSchedulesDao.getSchedule(topic, itemId);
    if (!mounted) return;

    final now = DateTime.now().toUtc();
    setState(() {
      _currentItemState = existing != null
          ? SrsCardState(
              cardId: '$topic:$itemId',
              due: existing.due,
              stability: existing.stability,
              difficulty: existing.difficulty,
              interval: existing.interval,
              lapses: existing.lapses,
              reps: existing.reps,
              state: existing.state,
              lastReview: existing.lastReview,
              step: existing.step,
            )
          : SrsCardState(cardId: '$topic:$itemId', due: now);
    });
  }

  String _ratingSublabel(int rating) {
    final state = _currentItemState;
    if (state == null || !_showIntervalHints) return '';
    final adapter = ref.read(fsrsAdapterProvider);
    final preview = adapter.review(state, rating);
    final now = DateTime.now().toUtc();
    final diff = preview.due.difference(now);
    return DurationFormatter.formatShort(diff);
  }

  void _rateAndAdvance(int rating) async {
    if (rating == 0) {
      await _rateAndAdvanceWithDelay(rating);
      return;
    }
    await ref
        .read(drillSessionProvider(widget.exerciseId).notifier)
        .submitAnswer(correct: rating > 0, rating: rating);
    if (!mounted) return;
    setState(() {
      _currentItemState = null;
    });
    ref.read(drillSessionProvider(widget.exerciseId).notifier).nextQuestion();
    _loadItemState();
    _createController();
  }

  Future<void> _rateAndAdvanceWithDelay(int rating) async {
    await ref
        .read(drillSessionProvider(widget.exerciseId).notifier)
        .submitAnswer(correct: false, rating: rating);
    if (!mounted) return;
    setState(() {
      _currentItemState = null;
    });
    await Future.delayed(kPostAgainAdvanceDelay);
    if (!mounted) return;
    ref.read(drillSessionProvider(widget.exerciseId).notifier).nextQuestion();
    _loadItemState();
    _createController();
  }

  String? _formatNextReview(DateTime? due) {
    if (due == null) return null;
    final now = DateTime.now().toUtc();
    final diff = due.difference(now);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return 'in ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'in ${diff.inHours} hr';
    if (diff.inDays == 1) return 'tomorrow';
    return 'in ${diff.inDays} days';
  }

  @override
  Widget build(BuildContext context) {
    final exerciseAsync = ref.watch(exerciseByIdProvider(widget.exerciseId));
    final drillState = ref.watch(drillSessionProvider(widget.exerciseId));
    final countsAsync = ref.watch(exerciseCountsProvider(widget.exerciseId));

    ref.listen<DrillSessionState>(
      drillSessionProvider(widget.exerciseId),
      (previous, next) {
        if (previous?.phase != DrillPhase.complete &&
            next.phase == DrillPhase.complete) {
          ref.invalidate(exerciseCountsProvider(widget.exerciseId));
        }
      },
    );

    return PopScope(
      canPop: !_started || drillState.phase == DrillPhase.complete,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showExitConfirmation(context, drillState);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: SessionAppBarTitle(
            title: exerciseAsync.valueOrNull?.title ?? 'Practice',
            subtitleParts: [
              widget.learnedOnly ? 'Practice Learned' : 'Review',
              '${drillState.currentQuestionIndex + 1}/${drillState.totalQuestions}',
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => _showExitConfirmation(context, drillState),
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
              return _buildCompleteSummary(
                context,
                drillState,
                countsAsync.valueOrNull,
              );
            }
            return _buildPracticeBody(context, drillState);
          },
        ),
        bottomNavigationBar: _buildBottomBar(context, drillState),
      ),
    );
  }

  Widget _buildPracticeBody(
    BuildContext context,
    DrillSessionState drillState,
  ) {
    final theme = Theme.of(context);
    final question = drillState.currentQuestion;
    final progress = drillState.progress;
    final ctrl = _controller;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: progress,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 32),

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

          if (ctrl != null)
            AnswerInputArea(
              controller: ctrl,
              nextReviewText: _formatNextReview(drillState.lastItemDue),
              feedbackExtra: question?.notationData != null
                  ? SimpleSheetMusicAdapter(
                      data: question!.notationData!,
                      height: 120,
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  Widget? _buildBottomBar(BuildContext context, DrillSessionState drillState) {
    if (!_started || drillState.phase == DrillPhase.complete) return null;

    final ctrl = _controller;
    if (ctrl == null) return null;

    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        if (ctrl.phase != AnswerPhase.feedback) return const SizedBox.shrink();

        // Wrong answers auto-advance with "Again" after a delay — no rating needed.
        if (ctrl.result == false) return const SizedBox.shrink();

        return AnswerActionBar(
          child: RatingButtons(
            onRate: _rateAndAdvance,
            sublabelBuilder: _ratingSublabel,
          ),
        );
      },
    );
  }

  Future<void> _showExitConfirmation(
    BuildContext context,
    DrillSessionState drillState,
  ) async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End practice session?'),
        content: Text(
          'You have completed ${drillState.currentQuestionIndex} of '
          '${drillState.totalQuestions} questions.',
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

  void _learnMore() {
    _restartPractice(ignoreNewCardLimit: true);
  }

  void _restartPractice({bool ignoreNewCardLimit = false}) {
    _controller?.dispose();
    _controller = null;
    setState(() {
      _started = false;
      _currentItemState = null;
    });
    _startPractice(
      ignoreNewCardLimit: ignoreNewCardLimit,
      newCardCount: widget.newCardCount,
    );
  }

  void _startDrill() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => DrillScreen(
          exerciseId: widget.exerciseId,
          selectedGroups: widget.selectedGroups,
        ),
      ),
    );
  }

  void _startLearn() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => ExerciseLearnScreen(
          exerciseId: widget.exerciseId,
          selectedGroups: widget.selectedGroups,
        ),
      ),
    );
  }

  Widget _buildCompleteSummary(
    BuildContext context,
    DrillSessionState drillState,
    ExerciseCounts? counts,
  ) {
    final theme = Theme.of(context);
    final isEmpty = drillState.totalQuestions == 0;
    final canReviewAgain = counts != null &&
        (counts.reviewCount > 0 || counts.newCount > 0);

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
              isEmpty ? 'All caught up!' : 'Practice Complete!',
              style: theme.textTheme.headlineLarge,
            ),
            const SizedBox(height: 16),
            Text(
              isEmpty
                  ? 'No cards to review or learn right now.'
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
            const SizedBox(height: 12),
            if (canReviewAgain) ...[
              OutlinedButton.icon(
                onPressed: _restartPractice,
                icon: const Icon(Icons.refresh),
                label: const Text('Review Again'),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _startDrill,
                      icon: const Icon(Icons.timer),
                      label: const Text('Drill'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _startLearn,
                      icon: const Icon(Icons.school),
                      label: const Text('Learn'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
