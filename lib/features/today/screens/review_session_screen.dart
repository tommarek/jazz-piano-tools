import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/answer_input/answer_action_bar.dart';
import '../../../core/answer_input/answer_input_area.dart';
import '../../../core/answer_input/answer_input_controller.dart';
import '../../../core/answer_input/answer_input_mode.dart';
import '../../../core/answer_input/duration_formatter.dart';
import '../../../core/answer_input/pitch_class_parser.dart';
import '../../../core/answer_input/rating_buttons.dart';
import '../../../core/constants/ui_timing.dart';
import '../../../core/constants/srs_defaults.dart';
import '../../../core/audio/audio_provider.dart';
import '../../../core/audio/pitched_note.dart';
import '../../../core/music/pitch_class.dart';
import '../../../domain/models/srs_card.dart';
import '../../../domain/models/srs_card_state.dart';
import '../../../domain/enums/answer_type.dart';
import '../../srs/providers/srs_provider.dart';
import '../../streak/providers/streak_provider.dart';
import '../providers/today_session_provider.dart';

class ReviewSessionScreen extends ConsumerStatefulWidget {
  final String? category;

  const ReviewSessionScreen({this.category, super.key});

  @override
  ConsumerState<ReviewSessionScreen> createState() =>
      _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends ConsumerState<ReviewSessionScreen> {
  int _currentIndex = 0;
  int _totalCards = 0;
  int _correctCount = 0;
  List<String> _cardIds = [];
  SrsCard? _currentCard;
  SrsCardState? _currentState;
  bool _isLoading = true;
  final _stopwatch = Stopwatch();

  AnswerInputController? _controller;
  bool _intervalAudioAnswered = false;
  bool? _intervalAudioCorrect;
  String? _intervalAudioSelected;
  bool _intervalAudioPlaying = false;
  String? _autoPlayedIntervalAudioCardId;

  static const _intervalLabels = [
    'm2', 'M2', 'm3', 'M3',
    'P4', 'TT', 'P5', 'm6',
    'M6', 'm7', 'M7', 'P8',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCards();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    final engine = ref.read(srsEngineProvider);
    final ids = widget.category == null
        ? await engine.getStudyQueueCardIds()
        : await engine.getDueCardIdsForCategory(widget.category!);
    if (!mounted) return;

    if (ids.isEmpty) {
      _navigateToSummary();
      return;
    }

    setState(() {
      _cardIds = ids;
      _totalCards = ids.length;
      _isLoading = false;
    });

    await _loadCurrentCard();
  }

  Future<void> _loadCurrentCard() async {
    if (_currentIndex >= _cardIds.length) {
      _navigateToSummary();
      return;
    }

    final engine = ref.read(srsEngineProvider);
    final (card, state) =
        await engine.getCardForReview(_cardIds[_currentIndex]);
    if (!mounted) return;

    setState(() {
      _currentCard = card;
      _currentState = state;
      _intervalAudioAnswered = false;
      _intervalAudioCorrect = null;
      _intervalAudioSelected = null;
      _intervalAudioPlaying = false;
      _autoPlayedIntervalAudioCardId = null;
    });

    _stopwatch.reset();
    _stopwatch.start();
    _createController(card);
    _autoPlayIntervalAudioIfNeeded(card);
  }

  void _createController(SrsCard card) {
    if (card.answerType == AnswerType.intervalAudio) {
      _controller?.dispose();
      _controller = null;
      setState(() {});
      return;
    }

    _controller?.dispose();

    // Use keyboard if answer contains parseable pitch classes, else selfReveal
    final hasPitches =
        PitchClassParser.extract(card.expectedAnswer).isNotEmpty;
    final mode =
        hasPitches ? AnswerInputMode.keyboard : AnswerInputMode.selfReveal;

    _controller = AnswerInputController(
      mode: mode,
      expectedAnswer: card.expectedAnswer,
      answerText: card.expectedAnswer,
      onResult: (correct) {
        _stopwatch.stop();
        setState(() {});
        if (!correct) {
          Future.delayed(kAutoRevealAgainDelay, () {
            if (mounted) _rateAndNext(0);
          });
        }
      },
    );
    setState(() {});
  }

  Future<void> _playIntervalAudioCard() async {
    await _playIntervalAudioCardInternal();
  }

  Future<bool> _playIntervalAudioCardInternal() async {
    final card = _currentCard;
    if (card == null || card.answerType != AnswerType.intervalAudio || _intervalAudioPlaying) {
      return false;
    }
    final meta = card.metadata;
    final rootPc = meta['rootPitchClass'] as int?;
    final semitones = meta['intervalSemitones'] as int?;
    final baseOctave = (meta['baseOctave'] as int?) ?? 4;
    if (rootPc == null || semitones == null) return false;

    final root = PitchedNote(PitchClass(rootPc), baseOctave);
    final top = root.transpose(semitones);
    final audio = ref.read(audioServiceProvider);
    final pattern = (meta['audioPattern'] as String?) ?? 'asc-unison-desc';

    setState(() => _intervalAudioPlaying = true);
    try {
      switch (pattern) {
        case 'ascending':
          await audio.playNote(root, durationMs: kIntervalAudioMelodicNoteMs);
          await Future<void>.delayed(const Duration(milliseconds: 60));
          await audio.playNote(top, durationMs: kIntervalAudioMelodicNoteMs);
          break;
        case 'harmonic':
          await audio.playChord(
            [root, top],
            durationMs: kIntervalAudioHarmonicChordMs,
          );
          break;
        case 'descending':
          await audio.playNote(top, durationMs: kIntervalAudioMelodicNoteMs);
          await Future<void>.delayed(const Duration(milliseconds: 60));
          await audio.playNote(root, durationMs: kIntervalAudioMelodicNoteMs);
          break;
        default:
          // Backward-compatible fallback for older seeded cards.
          await audio.playNote(root, durationMs: kIntervalAudioMelodicNoteMs);
          await Future<void>.delayed(const Duration(milliseconds: 60));
          await audio.playNote(top, durationMs: kIntervalAudioMelodicNoteMs);
          await Future<void>.delayed(const Duration(milliseconds: 180));
          await audio.playChord(
            [root, top],
            durationMs: kIntervalAudioHarmonicChordMs,
          );
          await Future<void>.delayed(const Duration(milliseconds: 120));
          await audio.playNote(top, durationMs: kIntervalAudioMelodicNoteMs);
          await Future<void>.delayed(const Duration(milliseconds: 60));
          await audio.playNote(root, durationMs: kIntervalAudioMelodicNoteMs);
      }
    } finally {
      if (mounted) setState(() => _intervalAudioPlaying = false);
    }
    return true;
  }

  void _autoPlayIntervalAudioIfNeeded(SrsCard card) {
    if (card.answerType != AnswerType.intervalAudio) return;
    if (_autoPlayedIntervalAudioCardId == card.id) return;
    _autoPlayedIntervalAudioCardId = card.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoPlayIntervalAudioDeferred(card.id);
    });
  }

  Future<void> _autoPlayIntervalAudioDeferred(String cardId) async {
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (!mounted || _currentCard?.id != cardId) return;
    final started = await _playIntervalAudioCardInternal();
    if (started) return;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted || _currentCard?.id != cardId) return;
    await _playIntervalAudioCardInternal();
  }

  Future<void> _submitIntervalAudioAnswer(String label) async {
    if (_intervalAudioAnswered) return;
    _stopwatch.stop();
    final correct = _currentCard?.expectedAnswer == label;
    setState(() {
      _intervalAudioAnswered = true;
      _intervalAudioCorrect = correct;
      _intervalAudioSelected = label;
    });
    if (!correct) {
      await Future<void>.delayed(kAutoRevealAgainDelay);
      if (mounted) {
        await _rateAndNext(0);
      }
    }
  }

  Future<void> _rateAndNext(int rating) async {
    final cardId = _cardIds[_currentIndex];
    final engine = ref.read(srsEngineProvider);
    await engine.recordReview(
      cardId,
      rating,
      _stopwatch.elapsedMilliseconds,
    );
    await _maybeMarkCategoryCompletion();
    ref.invalidate(dueCardIdsProvider);
    ref.invalidate(dueCardCountProvider);
    ref.invalidate(todaySessionProvider);
    ref.invalidate(todayDashboardCountsProvider);
    ref.invalidate(todayCategoryDashboardCountsProvider(TodayReviewCategory.learning));
    ref.invalidate(todayCategoryDashboardCountsProvider(TodayReviewCategory.ear));
    ref.invalidate(todayStreakProvider);

    if (rating >= 2) {
      _correctCount++;
    }

    _currentIndex++;
    await _extendQueueWithNewlyDueCards();
    if (_currentIndex >= _cardIds.length) {
      _navigateToSummary();
      return;
    }
    await _loadCurrentCard();
  }

  Future<void> _extendQueueWithNewlyDueCards() async {
    final engine = ref.read(srsEngineProvider);
    final dueIds = widget.category == null
        ? await engine.getDueCardIds()
        : await engine.getDueCardIdsForCategory(widget.category!);
    if (!mounted || dueIds.isEmpty) return;

    // Only avoid duplicates already pending in this session. Cards reviewed
    // earlier in the session may become due again (learning/relearning steps)
    // and should be re-added. Insert at the current position so newly due
    // cards are handled before stale pending tail items (e.g. new cards).
    final pendingIds = _cardIds.skip(_currentIndex).toSet();
    final toAppend = dueIds.where((id) => !pendingIds.contains(id)).toList();
    if (toAppend.isEmpty) return;

    setState(() {
      _cardIds.insertAll(_currentIndex, toAppend);
      _totalCards = _cardIds.length;
    });
  }

  Future<void> _maybeMarkCategoryCompletion() async {
    final category = widget.category;
    if (category == null) return;
    final engine = ref.read(srsEngineProvider);
    final stats = await engine.getDueQueueStatsForCategory(category);
    if (stats.totalDue > 0) return;

    final db = ref.read(appDatabaseProvider);
    final settings = await db.settingsDao.getSettings();
    final rolloverHour = settings?.dayRolloverHour ?? kDefaultDayRolloverHour;
    final dayKey = studyDayKeyNow(rolloverHour);
    await db.dailyCompletionsDao.upsertCompletion(
      studyDayKey: dayKey,
      category: category,
      completedAt: DateTime.now().toUtc(),
    );
  }

  void _navigateToSummary() {
    if (!mounted) return;
    context.pushReplacement('/summary', extra: {
      'cardsReviewed': _currentIndex,
      'correctCount': _correctCount,
    });
  }

  double get _progress =>
      _totalCards > 0 ? _currentIndex / _totalCards : 0.0;

  String _ratingSublabel(int rating) {
    final state = _currentState;
    if (state == null) return '';
    final adapter = ref.read(fsrsAdapterProvider);
    final preview = adapter.review(state, rating);
    final now = DateTime.now().toUtc();
    final diff = preview.due.difference(now);
    return DurationFormatter.formatShort(diff);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Review (${_currentIndex + 1}/$_totalCards)'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _showExitConfirmation(context),
        ),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: _progress,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildPhaseContent(context),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  Widget _buildPhaseContent(BuildContext context) {
    final theme = Theme.of(context);
    final card = _currentCard;
    final ctrl = _controller;

    if (card == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (card.answerType == AnswerType.intervalAudio) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                card.prompt,
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: _intervalAudioPlaying ? null : _playIntervalAudioCard,
            icon: Icon(_intervalAudioPlaying ? Icons.volume_up : Icons.replay),
            label: Text(_intervalAudioPlaying ? 'Playing...' : 'Play again'),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.5,
            children: [
              for (final label in _intervalLabels)
                _buildIntervalAnswerButton(label, card.expectedAnswer),
            ],
          ),
          if (_intervalAudioAnswered) ...[
            const SizedBox(height: 16),
            Card(
              color: (_intervalAudioCorrect ?? false)
                  ? theme.colorScheme.secondaryContainer
                  : theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  (_intervalAudioCorrect ?? false)
                      ? 'Correct: ${card.expectedAnswer}'
                      : 'You chose ${_intervalAudioSelected ?? ''} · Correct: ${card.expectedAnswer}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
          const Spacer(),
        ],
      );
    }

    if (ctrl == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              card.prompt,
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 24),

        AnswerInputArea(controller: ctrl),

        const Spacer(),
      ],
    );
  }

  Widget _buildIntervalAnswerButton(String label, String correctAnswer) {
    final selected = _intervalAudioSelected == label;
    final answered = _intervalAudioAnswered;
    final isCorrect = label == correctAnswer;
    final theme = Theme.of(context);
    Color? bg;
    Color? fg;
    if (answered) {
      if (isCorrect) {
        bg = theme.colorScheme.secondaryContainer;
        fg = theme.colorScheme.onSecondaryContainer;
      } else if (selected) {
        bg = theme.colorScheme.errorContainer;
        fg = theme.colorScheme.onErrorContainer;
      }
    }
    return FilledButton.tonal(
      onPressed: answered ? null : () => _submitIntervalAudioAnswer(label),
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        padding: EdgeInsets.zero,
      ),
      child: Text(label),
    );
  }

  Widget? _buildBottomBar(BuildContext context) {
    if (_isLoading || _currentCard == null) return null;
    final ctrl = _controller;
    final card = _currentCard;
    if (card?.answerType == AnswerType.intervalAudio) {
      if (_intervalAudioAnswered && _intervalAudioCorrect == true) {
        return AnswerActionBar(
          child: RatingButtons(
            onRate: _rateAndNext,
            sublabelBuilder: _ratingSublabel,
          ),
        );
      }
      return const SizedBox.shrink();
    }
    if (ctrl == null) return null;

    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        // Feedback phase: show rating buttons only for correct answers.
        // Wrong answers auto-advance with "Again" after a delay.
        if (ctrl.phase == AnswerPhase.feedback && ctrl.result != false) {
          return AnswerActionBar(
            child: RatingButtons(
              onRate: _rateAndNext,
              sublabelBuilder: _ratingSublabel,
            ),
          );
        }

        // Self-reveal input: "Show Answer" button
        if (ctrl.mode == AnswerInputMode.selfReveal) {
          return AnswerActionBar(
            child: FilledButton(
              onPressed: () {
                _stopwatch.stop();
                ctrl.revealAnswer();
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Show Answer'),
            ),
          );
        }

        // Keyboard input: no bottom bar (AnswerInputArea handles inline Submit)
        return const SizedBox.shrink();
      },
    );
  }

  Future<void> _showExitConfirmation(BuildContext context) async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End review session?'),
        content: Text(
          'You have reviewed $_currentIndex of $_totalCards cards. '
          'Remaining cards will still be due.',
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
      _navigateToSummary();
    }
  }
}
