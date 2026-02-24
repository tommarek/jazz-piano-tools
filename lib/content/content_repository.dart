import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'content_loader.dart';

class ContentRepository {
  final AppDatabase _db;
  final ContentLoader _loader;

  /// Bump this when exercise/content JSON changes to trigger re-seed.
  static const int currentContentVersion = 14;

  ContentRepository(this._db, this._loader);

  Future<void> ensureContentLoaded() async {
    final count = await _db.conceptsDao.getConceptCount();
    if (count == 0) {
      await _seedFromAssets();
      await _seedProgressionTiers();
    }

    // Seed default settings if empty
    final settings = await _db.settingsDao.getSettings();
    if (settings == null) {
      await _db.settingsDao.upsertSettings(
        const SettingsCompanion(contentVersion: Value(currentContentVersion)),
      );
    } else {
      // Seed progression tiers if empty (for upgrades)
      final tiers = await _db.progressionDao.getAllTiers();
      if (tiers.isEmpty) {
        await _seedProgressionTiers();
      }
      // Re-seed content if version is outdated
      await _reseedIfOutdated();
    }
  }

  Future<void> _reseedIfOutdated() async {
    final settings = await _db.settingsDao.getSettings();
    final dbVersion = settings?.contentVersion ?? 0;

    if (dbVersion < currentContentVersion) {
      await _reseedAllContent();
      await _db.settingsDao.upsertSettings(
        SettingsCompanion(contentVersion: Value(currentContentVersion)),
      );
    }
  }

  Future<void> _reseedAllContent() async {
    await _clearContentTables();
    await _seedFromAssets();
    await _seedProgressionTiers();
  }

  Future<void> _clearContentTables() async {
    // Clear content tables AND dependent user-progress tables that have
    // foreign keys into content. Without this, re-inserting content with
    // the same IDs causes UNIQUE constraint failures.
    await _db.transaction(() async {
      await _db.delete(_db.reviews).go();
      await _db.delete(_db.questionResults).go();
      await _db.delete(_db.exerciseAttempts).go();
      await _db.delete(_db.itemSchedules).go();
      await _db.delete(_db.cardStates).go();
      await _db.delete(_db.cards).go();
      await _db.delete(_db.decks).go();
      await _db.delete(_db.concepts).go();
      await _db.delete(_db.exercises).go();
      await _db.delete(_db.tierProgress).go();
      await _db.delete(_db.progressionTiers).go();
    });
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
            examples: c.examples.map((e) => jsonEncode(e)).toList(),
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
            parentId: Value(d.parentId),
            excludeFromDailyReview: const Value(false),
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
            due: DateTime.now().toUtc(),
            stability: 0.0,
            difficulty: 0.0,
            interval: 0,
            lapses: 0,
            reps: 0,
            state: 'new',
            lastReview: const Value(null),
            step: const Value(null),
          ),
        );
      }
    });
  }

  Future<void> _seedProgressionTiers() async {
    final tiers = await _loader.loadProgressionTiers();

    await _db.batch((batch) {
      for (final t in tiers) {
        batch.insert(
          _db.progressionTiers,
          ProgressionTiersCompanion.insert(
            id: t.id,
            topic: t.topic,
            tierNumber: t.tierNumber,
            title: t.title,
            config: t.config,
          ),
        );

        // Tier 1 of each topic is unlocked by default
        batch.insert(
          _db.tierProgress,
          TierProgressCompanion(
            tierId: Value(t.id),
            isUnlocked: Value(t.tierNumber == 1),
          ),
        );
      }
    });
  }

  Future<void> resetProgress() async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db.delete(_db.reviews).go();
      await _db.delete(_db.questionResults).go();
      await _db.delete(_db.exerciseAttempts).go();
      await _db.delete(_db.itemSchedules).go();
      await _db.delete(_db.cardStates).go();
      await _db.delete(_db.tierProgress).go();

      final cards = await _db.cardsDao.getAllCards();
      final tiers = await _db.progressionDao.getAllTiers();

      await _db.batch((batch) {
        for (final card in cards) {
          batch.insert(
            _db.cardStates,
            CardStatesCompanion.insert(
              cardId: card.id,
              due: now,
              stability: 0.0,
              difficulty: 0.0,
              interval: 0,
              lapses: 0,
              reps: 0,
              state: 'new',
              lastReview: const Value(null),
              step: const Value(null),
            ),
          );
        }
        for (final tier in tiers) {
          batch.insert(
            _db.tierProgress,
            TierProgressCompanion(
              tierId: Value(tier.id),
              isUnlocked: Value(tier.tierNumber == 1),
            ),
          );
        }
      });
    });
  }

  Future<void> resetDeckCardProgress(
    String deckId, {
    bool includeSubdecks = true,
  }) async {
    final deckIds = includeSubdecks
        ? await _db.decksDao.getDescendantDeckIdsInclusive(deckId)
        : [deckId];
    final cardIds = await _db.cardsDao.getCardIdsForDecks(deckIds);
    if (cardIds.isEmpty) return;

    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await (_db.delete(_db.reviews)..where((r) => r.cardId.isIn(cardIds))).go();
      await (_db.delete(_db.cardStates)..where((s) => s.cardId.isIn(cardIds))).go();

      await _db.batch((batch) {
        for (final cardId in cardIds) {
          batch.insert(
            _db.cardStates,
            CardStatesCompanion.insert(
              cardId: cardId,
              due: now,
              stability: 0.0,
              difficulty: 0.0,
              interval: 0,
              lapses: 0,
              reps: 0,
              state: 'new',
              lastReview: const Value(null),
              step: const Value(null),
            ),
          );
        }
      });
    });
  }

  Future<void> setDeckExcludedFromDailyReview(
    String deckId,
    bool excluded, {
    bool includeSubdecks = true,
  }) async {
    final deckIds = includeSubdecks
        ? await _db.decksDao.getDescendantDeckIdsInclusive(deckId)
        : [deckId];
    await _db.decksDao.setExcludedFromDailyReviewForDeckIds(deckIds, excluded);
  }
}
