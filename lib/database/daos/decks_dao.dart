import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/decks_table.dart';
import '../tables/cards_table.dart';

part 'decks_dao.g.dart';

@DriftAccessor(tables: [Decks, Cards])
class DecksDao extends DatabaseAccessor<AppDatabase> with _$DecksDaoMixin {
  DecksDao(super.db);

  Future<List<Deck>> getAllDecks() => select(decks).get();

  Future<Deck?> getDeckById(String id) {
    return (select(decks)..where((d) => d.id.equals(id))).getSingleOrNull();
  }

  Future<void> insertDeck(DecksCompanion companion) {
    return into(decks).insert(companion);
  }

  Future<(Deck, List<Card>)> getDeckWithCards(String deckId) async {
    final deck = await (select(decks)..where((d) => d.id.equals(deckId)))
        .getSingle();
    final deckCards = await (select(cards)
          ..where((c) => c.deckId.equals(deckId)))
        .get();
    return (deck, deckCards);
  }
}
