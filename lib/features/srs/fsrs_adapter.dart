import 'package:fsrs/fsrs.dart' as fsrs;

import '../../domain/models/srs_card_state.dart';

class FsrsAdapter {
  final fsrs.Scheduler _scheduler = fsrs.Scheduler();

  static const _ratingMap = {
    0: fsrs.Rating.again,
    1: fsrs.Rating.hard,
    2: fsrs.Rating.good,
    3: fsrs.Rating.easy,
  };

  SrsCardState review(SrsCardState currentState, int rating) {
    final card = _toFsrsCard(currentState);
    final fsrsRating = _ratingMap[rating] ?? fsrs.Rating.good;

    final result = _scheduler.reviewCard(
      card,
      fsrsRating,
      reviewDateTime: DateTime.now().toUtc(),
    );

    return _fromFsrsCard(result.card, currentState.cardId);
  }

  double getRetrievability(SrsCardState state) {
    final card = _toFsrsCard(state);
    return _scheduler.getCardRetrievability(
      card,
      currentDateTime: DateTime.now().toUtc(),
    );
  }

  fsrs.Card _toFsrsCard(SrsCardState state) {
    final fsrsState = switch (state.state) {
      'learning' => fsrs.State.learning,
      'review' => fsrs.State.review,
      'relearning' => fsrs.State.relearning,
      _ => fsrs.State.learning,
    };

    return fsrs.Card(
      cardId: state.cardId.hashCode,
      state: fsrsState,
      step: fsrsState == fsrs.State.review ? null : 0,
      stability: state.stability == 0.0 ? null : state.stability,
      difficulty: state.difficulty == 0.0 ? null : state.difficulty,
      due: state.due.toUtc(),
      lastReview: null,
    );
  }

  SrsCardState _fromFsrsCard(fsrs.Card card, String cardId) {
    final stateStr = switch (card.state) {
      fsrs.State.learning => 'learning',
      fsrs.State.review => 'review',
      fsrs.State.relearning => 'relearning',
    };

    return SrsCardState(
      cardId: cardId,
      due: card.due,
      stability: card.stability ?? 0.0,
      difficulty: card.difficulty ?? 0.0,
      interval: card.due.difference(DateTime.now().toUtc()).inDays,
      lapses: 0,
      reps: 1,
      state: stateStr,
    );
  }
}
