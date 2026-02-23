import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../core/answer_input/answer_action_bar.dart';
import '../../../core/answer_input/answer_input_area.dart';
import '../../../core/answer_input/answer_input_controller.dart';
import '../../../core/answer_input/answer_input_mode.dart';
import '../../../core/answer_input/duration_formatter.dart';
import '../../../core/answer_input/pitch_class_parser.dart';
import '../../../core/answer_input/rating_buttons.dart';
import '../../../core/constants/ui_timing.dart';
import '../../../domain/models/srs_card.dart';
import '../../../domain/models/srs_card_state.dart';
import '../../srs/providers/srs_provider.dart';
import '../../streak/providers/streak_provider.dart';
import '../providers/today_session_provider.dart';

class ReviewSessionScreen extends ConsumerStatefulWidget {
  const ReviewSessionScreen({super.key});

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
    final ids = await engine.getStudyQueueCardIds();
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
    });

    _stopwatch.reset();
    _stopwatch.start();
    _createController(card);
  }

  void _createController(SrsCard card) {
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

  Future<void> _rateAndNext(int rating) async {
    final cardId = _cardIds[_currentIndex];
    final engine = ref.read(srsEngineProvider);
    await engine.recordReview(
      cardId,
      rating,
      _stopwatch.elapsedMilliseconds,
    );
    ref.invalidate(dueCardIdsProvider);
    ref.invalidate(dueCardCountProvider);
    ref.invalidate(todaySessionProvider);
    ref.invalidate(todayDashboardCountsProvider);
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
    final dueIds = await engine.getDueCardIds();
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

    if (card == null || ctrl == null) {
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

  Widget? _buildBottomBar(BuildContext context) {
    if (_isLoading || _currentCard == null) return null;
    final ctrl = _controller;
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
