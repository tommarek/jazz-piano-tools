import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/database/app_database.dart';

AppDatabase _createTestDb() {
  return AppDatabase.forTesting(NativeDatabase.memory());
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = _createTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  group('DecksDao', () {
    test('insert and query deck', () async {
      await db.decksDao.insertDeck(DecksCompanion.insert(
        id: 'deck1',
        title: 'Major Triads',
        tags: ['triads', 'chords'],
      ));
      final decks = await db.decksDao.getAllDecks();
      expect(decks.length, 1);
      expect(decks.first.title, 'Major Triads');
      expect(decks.first.tags, ['triads', 'chords']);
    });
  });

  group('CardsDao', () {
    test('insert card and query by deck', () async {
      await db.decksDao.insertDeck(DecksCompanion.insert(
        id: 'deck1',
        title: 'Test Deck',
        tags: [],
      ));
      await db.cardsDao.insertCard(CardsCompanion.insert(
        id: 'card1',
        deckId: 'deck1',
        prompt: 'Play C major',
        expectedAnswer: 'C,E,G',
        answerType: 'pitch',
        metadata: {'root': 'C'},
      ));
      final cards = await db.cardsDao.getCardsByDeck('deck1');
      expect(cards.length, 1);
      expect(cards.first.prompt, 'Play C major');
    });

    test('getDueCards returns cards due in the past', () async {
      await db.decksDao.insertDeck(DecksCompanion.insert(
        id: 'deck1',
        title: 'Test',
        tags: [],
      ));
      await db.cardsDao.insertCard(CardsCompanion.insert(
        id: 'card1',
        deckId: 'deck1',
        prompt: 'Test prompt',
        expectedAnswer: 'answer',
        answerType: 'text',
        metadata: {},
      ));
      await db.cardsDao.upsertCardState(CardStatesCompanion.insert(
        cardId: 'card1',
        due: DateTime.now().subtract(const Duration(hours: 1)),
        stability: 0.0,
        difficulty: 0.0,
        interval: 0,
        lapses: 0,
        reps: 0,
        state: 'new',
      ));

      final dueCards = await db.cardsDao.getDueCards(DateTime.now());
      expect(dueCards.length, 1);
      expect(dueCards.first.id, 'card1');
    });

    test('getDueCards excludes future cards', () async {
      await db.decksDao.insertDeck(DecksCompanion.insert(
        id: 'deck1',
        title: 'Test',
        tags: [],
      ));
      await db.cardsDao.insertCard(CardsCompanion.insert(
        id: 'card1',
        deckId: 'deck1',
        prompt: 'Test',
        expectedAnswer: 'answer',
        answerType: 'text',
        metadata: {},
      ));
      await db.cardsDao.upsertCardState(CardStatesCompanion.insert(
        cardId: 'card1',
        due: DateTime.now().add(const Duration(days: 7)),
        stability: 5.0,
        difficulty: 3.0,
        interval: 7,
        lapses: 0,
        reps: 3,
        state: 'review',
      ));

      final dueCards = await db.cardsDao.getDueCards(DateTime.now());
      expect(dueCards, isEmpty);
    });

    test('upsertCardState updates existing state', () async {
      await db.decksDao.insertDeck(DecksCompanion.insert(
        id: 'deck1',
        title: 'Test',
        tags: [],
      ));
      await db.cardsDao.insertCard(CardsCompanion.insert(
        id: 'card1',
        deckId: 'deck1',
        prompt: 'Test',
        expectedAnswer: 'answer',
        answerType: 'text',
        metadata: {},
      ));

      await db.cardsDao.upsertCardState(CardStatesCompanion.insert(
        cardId: 'card1',
        due: DateTime.now(),
        stability: 0.0,
        difficulty: 0.0,
        interval: 0,
        lapses: 0,
        reps: 0,
        state: 'new',
      ));

      await db.cardsDao.upsertCardState(CardStatesCompanion.insert(
        cardId: 'card1',
        due: DateTime.now().add(const Duration(days: 3)),
        stability: 5.0,
        difficulty: 4.0,
        interval: 3,
        lapses: 0,
        reps: 1,
        state: 'review',
      ));

      final state = await db.cardsDao.getCardState('card1');
      expect(state, isNotNull);
      expect(state!.reps, 1);
      expect(state.state, 'review');
    });
  });

  group('ReviewsDao', () {
    test('insert and query review', () async {
      await db.decksDao.insertDeck(DecksCompanion.insert(
        id: 'deck1',
        title: 'Test',
        tags: [],
      ));
      await db.cardsDao.insertCard(CardsCompanion.insert(
        id: 'card1',
        deckId: 'deck1',
        prompt: 'Test',
        expectedAnswer: 'answer',
        answerType: 'text',
        metadata: {},
      ));
      await db.reviewsDao.insertReview(ReviewsCompanion.insert(
        id: 'r1',
        cardId: 'card1',
        timestamp: DateTime.now(),
        rating: 3,
        responseTimeMs: 2500,
      ));

      final reviews = await db.reviewsDao.getReviewsForCard('card1');
      expect(reviews.length, 1);
      expect(reviews.first.rating, 3);
    });
  });

  group('ConceptsDao', () {
    test('insert and search concepts', () async {
      await db.conceptsDao.insertConcept(ConceptsCompanion.insert(
        id: 'c1',
        title: 'Major Triads',
        summary: 'Learn about major triads',
        bodyMarkdown: '# Triads',
        examples: ['example1'],
        tags: ['chords'],
        level: 1,
        relatedExerciseIds: [],
        relatedCardDeckIds: [],
      ));

      final found = await db.conceptsDao.searchConcepts('triad');
      expect(found.length, 1);
      expect(found.first.title, 'Major Triads');

      final notFound = await db.conceptsDao.searchConcepts('scale');
      expect(notFound, isEmpty);
    });
  });
}
