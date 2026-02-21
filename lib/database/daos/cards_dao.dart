import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/cards_table.dart';
import '../tables/card_states_table.dart';

part 'cards_dao.g.dart';

@DriftAccessor(tables: [Cards, CardStates])
class CardsDao extends DatabaseAccessor<AppDatabase> with _$CardsDaoMixin {
  CardsDao(super.db);

  Future<List<Card>> getAllCards() => select(cards).get();

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
      ..where(cardStates.due.isSmallerOrEqualValue(now));
    return query.map((row) => row.readTable(cards)).get();
  }

  Future<void> upsertCardState(CardStatesCompanion companion) {
    return into(cardStates).insertOnConflictUpdate(companion);
  }

  Future<CardState?> getCardState(String cardId) {
    return (select(cardStates)..where((s) => s.cardId.equals(cardId)))
        .getSingleOrNull();
  }
}
