import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/answer_input/answer_action_bar.dart';
import '../../../core/answer_input/answer_input_area.dart';
import '../../../core/answer_input/answer_input_controller.dart';
import '../../../core/answer_input/answer_input_mode.dart';
import '../../../core/answer_input/duration_formatter.dart';
import '../../../core/answer_input/pitch_class_parser.dart';
import '../../../core/answer_input/rating_buttons.dart';
import '../../drill/widgets/session_app_bar_title.dart';
import '../../../app/providers.dart';
import '../../../database/app_database.dart' as drift;
import '../../../domain/models/srs_card.dart';
import '../../../domain/models/srs_card_state.dart';
import '../../srs/providers/srs_provider.dart';
import '../../today/screens/end_summary_screen.dart';

class DeckReviewScreen extends ConsumerStatefulWidget {
  final List<String> deckIds;
  final int questionCount;
  final bool isRandom;
  final int? newCardCount;
  final List<String>? cardIdsOverride;
  final String? modeLabel;

  const DeckReviewScreen({
    required this.deckIds,
    required this.questionCount,
    this.isRandom = false,
    this.newCardCount,
    this.cardIdsOverride,
    this.modeLabel,
    super.key,
  });

  @override
  ConsumerState<DeckReviewScreen> createState() => _DeckReviewScreenState();
}

class _DeckReviewScreenState extends ConsumerState<DeckReviewScreen> {
  int _currentIndex = 0;
  int _totalCards = 0;
  int _correctCount = 0;
  List<String> _cardIds = [];
  SrsCard? _currentCard;
  SrsCardState? _currentState;
  bool _isLoading = true;
  final _stopwatch = Stopwatch();

  AnswerInputController? _controller;
  bool _autoAdvancing = false;

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
    final db = ref.read(appDatabaseProvider);
    List<drift.Card> cards;

    if (widget.cardIdsOverride != null) {
      final ids = widget.cardIdsOverride!;
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
      return;
    }

    if (widget.isRandom) {
      cards = await db.cardsDao
          .getRandomCardsForDecks(widget.deckIds, widget.questionCount);
    } else {
      final now = DateTime.now().toUtc();
      final dueCards =
          await db.cardsDao.getDueCardsForDecks(widget.deckIds, now);
      final settings = await db.settingsDao.getSettings();
      final newCardsPerDay = settings?.newCardsPerDay ?? 5;
      final newCards = await db.cardsDao.getNewCardsForDecks(widget.deckIds);
      final limit = widget.newCardCount ?? newCardsPerDay;
      final cappedNew = newCards.take(limit).toList();
      cards = [...dueCards, ...cappedNew]..shuffle();
    }

    final ids = cards.take(widget.questionCount).map((c) => c.id).toList();
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
      _autoAdvancing = false;
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
          _handleIncorrect();
        }
      },
    );
    setState(() {});
  }

  Future<void> _handleIncorrect() async {
    // Re-queue card for another attempt later in the session.
    setState(() {
      _autoAdvancing = true;
      _cardIds.add(_cardIds[_currentIndex]);
      _totalCards = _cardIds.length;
    });
    // Auto-rate as "Again" and advance after 1s.
    await _rateAndNextWithDelay(0);
  }

  Future<void> _rateAndNext(int rating) async {
    if (rating == 0) {
      // Auto-Again: record and move on after a short pause.
      await _rateAndNextWithDelay(rating);
      return;
    }
    try {
      if (!widget.isRandom) {
        final engine = ref.read(srsEngineProvider);
        await engine.recordReview(
          _cardIds[_currentIndex],
          rating,
          _stopwatch.elapsedMilliseconds,
        );
      }
    } catch (_) {
      // Fall through to advance even if SRS write fails.
    }

    if (rating >= 2) {
      _correctCount++;
    }

    _advanceToNext();
  }

  Future<void> _rateAndNextWithDelay(int rating) async {
    try {
      if (!widget.isRandom) {
        final engine = ref.read(srsEngineProvider);
        await engine.recordReview(
          _cardIds[_currentIndex],
          rating,
          _stopwatch.elapsedMilliseconds,
        );
      }
    } catch (_) {}

    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    _advanceToNext();
  }

  void _advanceToNext() {
    _currentIndex++;
    if (_currentIndex >= _cardIds.length) {
      _navigateToSummary();
    } else {
      _loadCurrentCard();
    }
  }

  void _navigateToSummary() {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => EndSummaryScreen(
          cardsReviewed: _currentIndex,
          correctCount: _correctCount,
          onDone: () {
            final nav = Navigator.of(context, rootNavigator: true);
            nav.pop();
            nav.pop();
          },
        ),
      ),
    );
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
    final modeLabel =
        widget.modeLabel ?? (widget.isRandom ? 'Drill' : 'Review');

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(modeLabel)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: SessionAppBarTitle(
          title: modeLabel,
          subtitleParts: [
            '${_currentIndex + 1} of ${_totalCards}',
            '${(_totalCards > 0 ? (_correctCount / (_currentIndex > 0 ? _currentIndex : 1) * 100).round() : 0)}% correct',
          ],
        ),
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
        // Feedback phase: show rating buttons (unless auto-advancing)
        if ((ctrl.phase == AnswerPhase.feedback || ctrl.keyboardSubmitted) &&
            !_autoAdvancing) {
          return AnswerActionBar(
            child: RatingButtons(
              onRate: _rateAndNext,
              sublabelBuilder: widget.isRandom ? null : _ratingSublabel,
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
        title: const Text('End session?'),
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
