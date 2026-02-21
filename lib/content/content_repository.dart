import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'content_loader.dart';

class ContentRepository {
  final AppDatabase _db;
  final ContentLoader _loader;

  ContentRepository(this._db, this._loader);

  Future<void> ensureContentLoaded() async {
    final count = await _db.conceptsDao.getConceptCount();
    if (count == 0) {
      await _seedFromAssets();
    }
  }

  Future<void> _seedFromAssets() async {
    final concepts = await _loader.loadConcepts();
    final exercises = await _loader.loadExercises();
    final decks = await _loader.loadDecks();
    final cards = await _loader.loadAllCards();

    await _db.batch((batch) {
      for (final c in concepts) {
        batch.insert(
          _db.concepts,
          ConceptsCompanion.insert(
            id: c.id,
            title: c.title,
            summary: c.summary,
            bodyMarkdown: c.bodyMarkdown,
            examples: c.examples.map((e) => e.toString()).toList(),
            tags: c.tags,
            level: c.level,
            relatedExerciseIds: c.relatedExerciseIds,
            relatedCardDeckIds: c.relatedCardDeckIds,
          ),
        );
      }

      for (final e in exercises) {
        batch.insert(
          _db.exercises,
          ExercisesCompanion.insert(
            id: e.id,
            title: e.title,
            mode: e.mode.name,
            inputType: e.inputType.name,
            generatorId: e.generatorId,
            config: e.config,
            acceptanceRules: e.acceptanceRules,
            scoringRules: e.scoringRules,
            tags: e.tags,
            level: e.level,
            estimatedMinutes: e.estimatedMinutes,
          ),
        );
      }

      for (final d in decks) {
        batch.insert(
          _db.decks,
          DecksCompanion.insert(
            id: d.id,
            title: d.title,
            tags: d.tags,
            sourceConceptId: Value(d.sourceConceptId),
          ),
        );
      }

      for (final card in cards) {
        batch.insert(
          _db.cards,
          CardsCompanion.insert(
            id: card.id,
            deckId: card.deckId,
            prompt: card.prompt,
            expectedAnswer: card.expectedAnswer,
            answerType: card.answerType.name,
            metadata: card.metadata,
          ),
        );
        batch.insert(
          _db.cardStates,
          CardStatesCompanion.insert(
            cardId: card.id,
            due: DateTime.now(),
            stability: 0.0,
            difficulty: 0.0,
            interval: 0,
            lapses: 0,
            reps: 0,
            state: 'new',
          ),
        );
      }
    });
  }
}
