import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/providers.dart';

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
