import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/providers.dart';
import '../../../database/app_database.dart';

part 'deck_review_provider.g.dart';

class DeckStats {
  final String deckId;
  final String title;
  final int totalCards;
  final int dueCards;
  final int newCards;

  const DeckStats({
    required this.deckId,
    required this.title,
    required this.totalCards,
    required this.dueCards,
    required this.newCards,
  });
}

class DeckTreeNode {
  final Deck deck;
  final List<DeckTreeNode> children;
  final int totalCards;
  final int dueCards;
  final int newCards;
  final int newCardsRaw;

  const DeckTreeNode({
    required this.deck,
    required this.children,
    required this.totalCards,
    required this.dueCards,
    required this.newCards,
    required this.newCardsRaw,
  });
}

@riverpod
Future<List<DeckStats>> conceptDeckStats(
  ConceptDeckStatsRef ref,
  List<String> deckIds,
) async {
  final db = ref.watch(appDatabaseProvider);
  final now = DateTime.now().toUtc();
  final settings = await db.settingsDao.getSettings();
  final newCardsPerDay = settings?.newCardsPerDay ?? 5;

  final stats = <DeckStats>[];
  for (final deckId in deckIds) {
    final deck = await db.decksDao.getDeckById(deckId);
    if (deck == null) continue;

    final totalCards = await db.cardsDao.getCardCountForDeck(deckId);
    final dueCards = await db.cardsDao.getDueCardsForDeck(deckId, now);
    final newCards = await db.cardsDao.getNewCardsForDeck(deckId);

    stats.add(DeckStats(
      deckId: deckId,
      title: deck.title,
      totalCards: totalCards,
      dueCards: dueCards.length,
      newCards: newCards.length.clamp(0, newCardsPerDay),
    ));
  }

  return stats;
}

@riverpod
Future<List<DeckTreeNode>> deckTreeStats(
  DeckTreeStatsRef ref,
  List<String> rootDeckIds,
) async {
  final db = ref.watch(appDatabaseProvider);
  final now = DateTime.now().toUtc();
  final settings = await db.settingsDao.getSettings();
  final newCardsPerDay = settings?.newCardsPerDay ?? 5;

  final decks = await db.decksDao.getAllDecks();
  final deckById = {for (final d in decks) d.id: d};
  final childrenMap = <String?, List<Deck>>{};
  for (final deck in decks) {
    childrenMap.putIfAbsent(deck.parentId, () => []).add(deck);
  }

  Future<DeckTreeNode> buildNode(Deck deck) async {
    final totalCards = await db.cardsDao.getCardCountForDeck(deck.id);
    final dueCards =
        await db.cardsDao.getDueCardsForDeck(deck.id, now);
    final newCards =
        await db.cardsDao.getNewCardsForDeck(deck.id);

    final children = <DeckTreeNode>[];
    for (final child in childrenMap[deck.id] ?? const []) {
      children.add(await buildNode(child));
    }

    final total = totalCards +
        children.fold<int>(0, (sum, n) => sum + n.totalCards);
    final due = dueCards.length +
        children.fold<int>(0, (sum, n) => sum + n.dueCards);
    final newRaw = newCards.length +
        children.fold<int>(0, (sum, n) => sum + n.newCardsRaw);
    final newCapped = newRaw.clamp(0, newCardsPerDay);

    return DeckTreeNode(
      deck: deck,
      children: children,
      totalCards: total,
      dueCards: due,
      newCards: newCapped,
      newCardsRaw: newRaw,
    );
  }

  final nodes = <DeckTreeNode>[];
  for (final rootId in rootDeckIds) {
    final deck = deckById[rootId];
    if (deck == null) continue;
    nodes.add(await buildNode(deck));
  }
  return nodes;
}
