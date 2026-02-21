import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../srs/providers/srs_provider.dart';
import '../../../domain/models/srs_card.dart';
import 'end_summary_screen.dart';

enum ReviewPhase { prompt, answer, feedback }

class ReviewSessionScreen extends ConsumerStatefulWidget {
  const ReviewSessionScreen({super.key});

  @override
  ConsumerState<ReviewSessionScreen> createState() =>
      _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends ConsumerState<ReviewSessionScreen> {
  ReviewPhase _phase = ReviewPhase.prompt;
  int _currentIndex = 0;
  int _totalCards = 0;
  int _correctCount = 0;
  List<String> _cardIds = [];
  SrsCard? _currentCard;
  String? _userAnswer;
  bool _isLoading = true;
  final _answerController = TextEditingController();
  final _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCards();
    });
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    final engine = ref.read(srsEngineProvider);
    final ids = await engine.getDueCardIds();
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
    final (card, _) = await engine.getCardForReview(_cardIds[_currentIndex]);
    if (!mounted) return;

    setState(() {
      _currentCard = card;
      _phase = ReviewPhase.prompt;
      _userAnswer = null;
      _answerController.clear();
    });

    _stopwatch.reset();
    _stopwatch.start();
  }

  void _submitAnswer() {
    _stopwatch.stop();
    setState(() {
      _userAnswer = _answerController.text.trim();
      _phase = ReviewPhase.feedback;
    });
  }

  Future<void> _rateAndNext(int rating) async {
    final engine = ref.read(srsEngineProvider);
    await engine.recordReview(
      _cardIds[_currentIndex],
      rating,
      _stopwatch.elapsedMilliseconds,
    );

    // Rating 3 (Good) or 4 (Easy) counts as correct
    if (rating >= 3) {
      _correctCount++;
    }

    _currentIndex++;
    if (_currentIndex >= _cardIds.length) {
      _navigateToSummary();
    } else {
      await _loadCurrentCard();
    }
  }

  void _navigateToSummary() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => EndSummaryScreen(
          cardsReviewed: _currentIndex,
          correctCount: _correctCount,
        ),
      ),
    );
  }

  double get _progress =>
      _totalCards > 0 ? _currentIndex / _totalCards : 0.0;

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
          // Progress bar
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
    );
  }

  Widget _buildPhaseContent(BuildContext context) {
    final theme = Theme.of(context);
    final card = _currentCard;

    if (card == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),

        // Prompt
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

        // Answer / feedback area
        if (_phase == ReviewPhase.prompt || _phase == ReviewPhase.answer) ...[
          TextField(
            controller: _answerController,
            decoration: const InputDecoration(
              hintText: 'Type your answer...',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            onSubmitted: (_) => _submitAnswer(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _answerController.text.trim().isNotEmpty
                ? _submitAnswer
                : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Show Answer'),
          ),
        ],

        if (_phase == ReviewPhase.feedback) ...[
          // Show expected answer
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Expected Answer',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    card.expectedAnswer,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  if (_userAnswer != null && _userAnswer!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Your answer: $_userAnswer',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Rating buttons
          Text(
            'How well did you know this?',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _RatingButton(
                label: 'Again',
                color: theme.colorScheme.error,
                onPressed: () => _rateAndNext(1),
              ),
              const SizedBox(width: 8),
              _RatingButton(
                label: 'Hard',
                color: Colors.orange,
                onPressed: () => _rateAndNext(2),
              ),
              const SizedBox(width: 8),
              _RatingButton(
                label: 'Good',
                color: Colors.green,
                onPressed: () => _rateAndNext(3),
              ),
              const SizedBox(width: 8),
              _RatingButton(
                label: 'Easy',
                color: theme.colorScheme.primary,
                onPressed: () => _rateAndNext(4),
              ),
            ],
          ),
        ],

        const Spacer(),
      ],
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

class _RatingButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _RatingButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(label),
      ),
    );
  }
}
