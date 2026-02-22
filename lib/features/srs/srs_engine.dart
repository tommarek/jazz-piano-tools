import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../database/app_database.dart';
import '../../domain/enums/answer_type.dart';
import '../../domain/models/srs_card.dart' as domain;
import '../../domain/models/srs_card_state.dart' as domain;
import 'fsrs_adapter.dart';

class SrsEngine {
  final AppDatabase _db;
  final FsrsAdapter _adapter;
  /// Optional callback invoked after a review is recorded, so providers
  /// watching due-card state can be invalidated.
  void Function()? onReviewRecorded;
  static const _uuid = Uuid();

  SrsEngine(this._db, this._adapter);

  Future<List<String>> getDueCardIds() async {
    final now = DateTime.now().toUtc();
    final dueCards = await _db.cardsDao.getDueCards(now);
    final newCards = await _db.cardsDao.getNewCardsForDecks(
      (await _db.decksDao.getAllDecks()).map((d) => d.id).toList(),
    );
    final dueIds = dueCards.map((c) => c.id).toSet();
    // Include new cards that aren't already in the due set
    for (final card in newCards) {
      dueIds.add(card.id);
    }
    return dueIds.toList();
  }

  Future<(domain.SrsCard, domain.SrsCardState)> getCardForReview(
    String cardId,
  ) async {
    final card = await _db.cardsDao.getCardById(cardId);
    if (card == null) {
      throw StateError('Card not found: $cardId');
    }
    final state = await _db.cardsDao.getCardState(cardId);

    final domainCard = domain.SrsCard(
      id: card.id,
      deckId: card.deckId,
      prompt: card.prompt,
      expectedAnswer: card.expectedAnswer,
      answerType: AnswerType.values.byName(card.answerType),
      metadata: card.metadata,
    );

    final domainState = state != null
        ? domain.SrsCardState(
            cardId: state.cardId,
            due: state.due,
            stability: state.stability,
            difficulty: state.difficulty,
            interval: state.interval,
            lapses: state.lapses,
            reps: state.reps,
            state: state.state,
            lastReview: state.lastReview,
            step: state.step,
          )
        : domain.SrsCardState(
            cardId: cardId,
            due: DateTime.now().toUtc(),
          );

    return (domainCard, domainState);
  }

  Future<domain.SrsCardState> recordReview(
    String cardId,
    int rating,
    int responseTimeMs,
  ) async {
    final now = DateTime.now().toUtc();
    final (_, currentState) = await getCardForReview(cardId);
    final newState = _adapter.review(currentState, rating, now: now);

    await _db.transaction(() async {
      await _db.cardsDao.upsertCardState(CardStatesCompanion.insert(
        cardId: cardId,
        due: newState.due,
        stability: newState.stability,
        difficulty: newState.difficulty,
        interval: newState.interval,
        lapses: newState.lapses,
        reps: newState.reps,
        state: newState.state,
        lastReview: Value(newState.lastReview),
        step: Value(newState.step),
      ));

      await _db.reviewsDao.insertReview(ReviewsCompanion.insert(
        id: _uuid.v4(),
        cardId: cardId,
        timestamp: now,
        rating: rating,
        responseTimeMs: responseTimeMs,
      ));
    });

    onReviewRecorded?.call();
    return newState;
  }
}
