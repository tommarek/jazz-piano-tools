import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/decks_table.dart';
import '../tables/cards_table.dart';

part 'decks_dao.g.dart';

@DriftAccessor(tables: [Decks, Cards])
class DecksDao extends DatabaseAccessor<AppDatabase> with _$DecksDaoMixin {
  DecksDao(super.db);

  Future<List<Deck>> getAllDecks() => select(decks).get();

  Future<List<String>> getExcludedFromDailyReviewDeckIds() async {
    final rows =
        await (select(decks)..where((d) => d.excludeFromDailyReview.equals(true)))
            .get();
    return rows.map((d) => d.id).toList();
  }

  Future<Deck?> getDeckById(String id) {
    return (select(decks)..where((d) => d.id.equals(id))).getSingleOrNull();
  }

  Future<List<Deck>> getDecksByIds(List<String> ids) {
    if (ids.isEmpty) return Future.value(const []);
    return (select(decks)..where((d) => d.id.isIn(ids))).get();
  }

  Future<void> insertDeck(DecksCompanion companion) {
    return into(decks).insert(companion);
  }

  Future<void> setExcludedFromDailyReviewForDeckIds(
    List<String> deckIds,
    bool excluded,
  ) async {
    if (deckIds.isEmpty) return;
    await (update(decks)..where((d) => d.id.isIn(deckIds))).write(
      DecksCompanion(excludeFromDailyReview: Value(excluded)),
    );
  }

  Future<List<String>> getDescendantDeckIdsInclusive(String deckId) async {
    final all = await getAllDecks();
    final children = <String?, List<Deck>>{};
    for (final deck in all) {
      children.putIfAbsent(deck.parentId, () => []).add(deck);
    }

    final result = <String>[];
    void visit(String id) {
      result.add(id);
      for (final child in children[id] ?? const <Deck>[]) {
        visit(child.id);
      }
    }

    visit(deckId);
    return result;
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
