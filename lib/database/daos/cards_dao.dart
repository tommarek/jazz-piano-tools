import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/cards_table.dart';
import '../tables/card_states_table.dart';

part 'cards_dao.g.dart';

@DriftAccessor(tables: [Cards, CardStates])
class CardsDao extends DatabaseAccessor<AppDatabase> with _$CardsDaoMixin {
  CardsDao(super.db);

  Future<List<Card>> getAllCards() => select(cards).get();

  Future<Card?> getCardById(String cardId) {
    return (select(cards)..where((c) => c.id.equals(cardId)))
        .getSingleOrNull();
  }

  Future<List<Card>> getCardsByDeck(String deckId) {
    return (select(cards)..where((c) => c.deckId.equals(deckId))).get();
  }

  Future<void> insertCard(CardsCompanion companion) {
    return into(cards).insert(companion);
  }

  Future<List<Card>> getDueCards(DateTime now) {
    final query = select(cards).join([
      innerJoin(cardStates, cardStates.cardId.equalsExp(cards.id)),
    ])
      ..where(
        cardStates.due.isSmallerOrEqualValue(now) &
            cardStates.state.isNotValue('new'),
      );
    return query.map((row) => row.readTable(cards)).get();
  }

  Future<List<String>> getDueLearningCardIds(
    DateTime now, {
    Duration learnAhead = Duration.zero,
  }) async {
    final dueBy = now.add(learnAhead);
    final query = select(cards).join([
      innerJoin(cardStates, cardStates.cardId.equalsExp(cards.id)),
    ])
      ..where(
        cardStates.due.isSmallerOrEqualValue(dueBy) &
            (cardStates.state.equals('learning') |
                cardStates.state.equals('relearning')),
      );
    final rows = await query.get();
    return rows.map((r) => r.readTable(cards).id).toList();
  }

  Future<List<String>> getDueReviewCardIds(DateTime now) async {
    final query = select(cards).join([
      innerJoin(cardStates, cardStates.cardId.equalsExp(cards.id)),
    ])
      ..where(
        cardStates.due.isSmallerOrEqualValue(now) &
            cardStates.state.equals('review'),
      );
    final rows = await query.get();
    return rows.map((r) => r.readTable(cards).id).toList();
  }

  Future<List<String>> getNewCardIds({int? limit}) async {
    final query = select(cards).join([
      innerJoin(cardStates, cardStates.cardId.equalsExp(cards.id)),
    ])
      ..where(cardStates.state.equals('new'));
    if (limit != null) {
      query.limit(limit);
    }
    final rows = await query.get();
    return rows.map((r) => r.readTable(cards).id).toList();
  }

  Future<void> upsertCardState(CardStatesCompanion companion) {
    return into(cardStates).insertOnConflictUpdate(companion);
  }

  Future<CardState?> getCardState(String cardId) {
    return (select(cardStates)..where((s) => s.cardId.equals(cardId)))
        .getSingleOrNull();
  }

  Future<int> getCardCountForDeck(String deckId) async {
    final count = cards.id.count();
    final query = selectOnly(cards)..addColumns([count]);
    query.where(cards.deckId.equals(deckId));
    final result = await query.getSingle();
    return result.read(count)!;
  }

  Future<int> getLearnedCardCountForDeck(String deckId) async {
    final count = cards.id.count();
    final query = selectOnly(cards)
      ..addColumns([count])
      ..join([
        innerJoin(cardStates, cardStates.cardId.equalsExp(cards.id)),
      ])
      ..where(
        cards.deckId.equals(deckId) & cardStates.state.isNotValue('new'),
      );
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  Future<int> getLearnedNotDueCardCountForDeck(
    String deckId,
    DateTime now,
  ) async {
    final count = cards.id.count();
    final query = selectOnly(cards)
      ..addColumns([count])
      ..join([
        innerJoin(cardStates, cardStates.cardId.equalsExp(cards.id)),
      ])
      ..where(
        cards.deckId.equals(deckId) &
            cardStates.state.equals('review') &
            cardStates.due.isBiggerThanValue(now),
      );
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  Future<List<Card>> getDueCardsForDeck(String deckId, DateTime now) {
    final query = select(cards).join([
      innerJoin(cardStates, cardStates.cardId.equalsExp(cards.id)),
    ])
      ..where(cards.deckId.equals(deckId) &
          cardStates.due.isSmallerOrEqualValue(now) &
          cardStates.state.isNotValue('new'));
    return query.map((row) => row.readTable(cards)).get();
  }

  Future<List<Card>> getNewCardsForDeck(String deckId) {
    final query = select(cards).join([
      innerJoin(cardStates, cardStates.cardId.equalsExp(cards.id)),
    ])
      ..where(cards.deckId.equals(deckId) &
          cardStates.state.equals('new'));
    return query.map((row) => row.readTable(cards)).get();
  }

  Future<List<Card>> getDueCardsForDecks(
      List<String> deckIds, DateTime now) {
    final query = select(cards).join([
      innerJoin(cardStates, cardStates.cardId.equalsExp(cards.id)),
    ])
      ..where(cards.deckId.isIn(deckIds) &
          cardStates.due.isSmallerOrEqualValue(now) &
          cardStates.state.isNotValue('new'));
    return query.map((row) => row.readTable(cards)).get();
  }

  Future<List<Card>> getNewCardsForDecks(List<String> deckIds) {
    final query = select(cards).join([
      innerJoin(cardStates, cardStates.cardId.equalsExp(cards.id)),
    ])
      ..where(cards.deckId.isIn(deckIds) &
          cardStates.state.equals('new'));
    return query.map((row) => row.readTable(cards)).get();
  }

  Future<List<Card>> getRandomCardsForDecks(
      List<String> deckIds, int count) async {
    final allCards =
        await (select(cards)..where((c) => c.deckId.isIn(deckIds))).get();
    allCards.shuffle();
    return allCards.take(count).toList();
  }

  Future<List<Card>> getHardCardsForDecks(
    List<String> deckIds,
    double stabilityThreshold,
    int count,
  ) async {
    final query = select(cards).join([
      innerJoin(cardStates, cardStates.cardId.equalsExp(cards.id)),
    ])
      ..where(
        cards.deckId.isIn(deckIds) &
            cardStates.state.isNotValue('new') &
            cardStates.stability.isSmallerThanValue(stabilityThreshold),
      )
      ..orderBy([
        OrderingTerm(expression: cardStates.stability, mode: OrderingMode.asc),
      ]);

    final results = await query.map((row) => row.readTable(cards)).get();
    return results.take(count).toList();
  }
}
