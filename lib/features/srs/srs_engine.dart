import 'package:uuid/uuid.dart';

import '../../database/app_database.dart';
import '../../domain/enums/answer_type.dart';
import '../../domain/models/srs_card.dart' as domain;
import '../../domain/models/srs_card_state.dart' as domain;
import 'fsrs_adapter.dart';

class SrsEngine {
  final AppDatabase _db;
  final FsrsAdapter _adapter;
  static const _uuid = Uuid();

  SrsEngine(this._db, this._adapter);

  Future<List<String>> getDueCardIds() async {
    final dueCards = await _db.cardsDao.getDueCards(DateTime.now());
    return dueCards.map((c) => c.id).toList();
  }

  Future<(domain.SrsCard, domain.SrsCardState)> getCardForReview(
    String cardId,
  ) async {
    final allCards = await _db.cardsDao.getAllCards();
    final card = allCards.firstWhere((c) => c.id == cardId);
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
          )
        : domain.SrsCardState(
            cardId: cardId,
            due: DateTime.now(),
          );

    return (domainCard, domainState);
  }

  Future<domain.SrsCardState> recordReview(
    String cardId,
    int rating,
    int responseTimeMs,
  ) async {
    final (_, currentState) = await getCardForReview(cardId);
    final newState = _adapter.review(currentState, rating);

    await _db.cardsDao.upsertCardState(CardStatesCompanion.insert(
      cardId: cardId,
      due: newState.due,
      stability: newState.stability,
      difficulty: newState.difficulty,
      interval: newState.interval,
      lapses: newState.lapses,
      reps: newState.reps,
      state: newState.state,
    ));

    await _db.reviewsDao.insertReview(ReviewsCompanion.insert(
      id: _uuid.v4(),
      cardId: cardId,
      timestamp: DateTime.now(),
      rating: rating,
      responseTimeMs: responseTimeMs,
    ));

    return newState;
  }
}
