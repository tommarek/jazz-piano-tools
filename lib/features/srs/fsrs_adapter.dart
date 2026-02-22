import 'package:fsrs/fsrs.dart' as fsrs;

import '../../domain/models/srs_card_state.dart';

class FsrsAdapter {
  final fsrs.Scheduler _scheduler;

  FsrsAdapter({double desiredRetention = 0.9})
      : _scheduler = fsrs.Scheduler(desiredRetention: desiredRetention);

  static const _ratingMap = {
    0: fsrs.Rating.again,
    1: fsrs.Rating.hard,
    2: fsrs.Rating.good,
    3: fsrs.Rating.easy,
  };

  SrsCardState review(SrsCardState currentState, int rating, {DateTime? now}) {
    now ??= DateTime.now().toUtc();
    final card = _toFsrsCard(currentState);
    final fsrsRating = _ratingMap[rating] ?? fsrs.Rating.good;

    final result = _scheduler.reviewCard(
      card,
      fsrsRating,
      reviewDateTime: now,
    );

    return _fromFsrsCard(
      result.card,
      currentState.cardId,
      currentState,
      rating,
      now,
    );
  }

  double getRetrievability(SrsCardState state) {
    // New/unreviewed cards have no retrievability yet
    if (state.stability == 0.0 || state.lastReview == null) {
      return 0.0;
    }
    final card = _toFsrsCard(state);
    return _scheduler.getCardRetrievability(
      card,
      currentDateTime: DateTime.now().toUtc(),
    );
  }

  fsrs.Card _toFsrsCard(SrsCardState state) {
    final fsrsState = switch (state.state) {
      'new' => fsrs.State.learning,
      'learning' => fsrs.State.learning,
      'review' => fsrs.State.review,
      'relearning' => fsrs.State.relearning,
      _ => fsrs.State.learning,
    };

    return fsrs.Card(
      cardId: state.cardId.hashCode,
      state: fsrsState,
      step: state.step ?? (fsrsState == fsrs.State.review ? null : 0),
      stability: state.stability == 0.0 ? null : state.stability,
      difficulty: state.difficulty == 0.0 ? null : state.difficulty,
      due: state.due.toUtc(),
      lastReview: state.lastReview?.toUtc(),
    );
  }

  SrsCardState _fromFsrsCard(
    fsrs.Card card,
    String cardId,
    SrsCardState previous,
    int rating,
    DateTime now,
  ) {
    final stateStr = switch (card.state) {
      fsrs.State.learning => 'learning',
      fsrs.State.review => 'review',
      fsrs.State.relearning => 'relearning',
    };

    final intervalDays = card.due.difference(now).inDays;
    // Only count a lapse when the card was in 'review' state and the user
    // forgot it (rating = Again). Learning-phase "Again" ratings are not
    // true lapses and should not inflate the lapse count.
    final isLapse = rating == 0 && previous.state == 'review';
    final newLapses = previous.lapses + (isLapse ? 1 : 0);
    final newReps = previous.reps + 1;

    return SrsCardState(
      cardId: cardId,
      due: card.due,
      stability: card.stability ?? 0.0,
      difficulty: card.difficulty ?? 0.0,
      interval: intervalDays < 0 ? 0 : intervalDays,
      lapses: newLapses,
      reps: newReps,
      state: stateStr,
      lastReview: now,
      step: card.step,
    );
  }
}
