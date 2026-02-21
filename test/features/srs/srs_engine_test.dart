import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/database/app_database.dart';
import 'package:jazz_piano_tools/features/srs/fsrs_adapter.dart';
import 'package:jazz_piano_tools/features/srs/srs_engine.dart';

void main() {
  late AppDatabase db;
  late SrsEngine engine;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    engine = SrsEngine(db, FsrsAdapter());

    // Seed test data: deck + 3 cards all due now
    await db.decksDao.insertDeck(DecksCompanion.insert(
      id: 'deck1',
      title: 'Test',
      tags: [],
    ));
    for (var i = 1; i <= 3; i++) {
      await db.cardsDao.insertCard(CardsCompanion.insert(
        id: 'card$i',
        deckId: 'deck1',
        prompt: 'Prompt $i',
        expectedAnswer: 'answer$i',
        answerType: 'text',
        metadata: {},
      ));
      await db.cardsDao.upsertCardState(CardStatesCompanion.insert(
        cardId: 'card$i',
        due: DateTime.now().subtract(const Duration(hours: 1)),
        stability: 0.0,
        difficulty: 0.0,
        interval: 0,
        lapses: 0,
        reps: 0,
        state: 'new',
      ));
    }
  });

  tearDown(() async {
    await db.close();
  });

  group('SrsEngine', () {
    test('getDueCardIds returns all due cards', () async {
      final ids = await engine.getDueCardIds();
      expect(ids.length, 3);
    });

    test('recordReview updates card state in DB', () async {
      final newState = await engine.recordReview('card1', 2, 2000);
      expect(newState.state, isNot('new'));
      expect(newState.due.isAfter(DateTime.now()), isTrue);

      // Check that review was inserted
      final reviews = await db.reviewsDao.getReviewsForCard('card1');
      expect(reviews.length, 1);
      expect(reviews.first.rating, 2);
    });

    test('after review with good, card is no longer due', () async {
      await engine.recordReview('card1', 2, 2000);
      final ids = await engine.getDueCardIds();
      expect(ids, isNot(contains('card1')));
      expect(ids.length, 2);
    });

    test('after review with again, card stays due or very soon', () async {
      final newState = await engine.recordReview('card1', 0, 1000);
      // Card should still be due soon (within a day)
      final diff = newState.due.difference(DateTime.now());
      expect(diff.inDays, lessThan(1));
    });
  });
}
