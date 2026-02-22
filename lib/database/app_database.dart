import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'converters.dart';
import 'tables/decks_table.dart';
import 'tables/cards_table.dart';
import 'tables/card_states_table.dart';
import 'tables/reviews_table.dart';
import 'tables/concepts_table.dart';
import 'tables/exercises_table.dart';
import 'tables/exercise_attempts_table.dart';
import 'tables/progression_tiers_table.dart';
import 'tables/tier_progress_table.dart';
import 'tables/question_results_table.dart';
import 'tables/settings_table.dart';
import 'tables/item_schedules_table.dart';
import 'tables/session_templates_table.dart';

import 'daos/cards_dao.dart';
import 'daos/decks_dao.dart';
import 'daos/reviews_dao.dart';
import 'daos/concepts_dao.dart';
import 'daos/exercises_dao.dart';
import 'daos/progression_dao.dart';
import 'daos/question_results_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/item_schedules_dao.dart';
import 'daos/session_templates_dao.dart';

export 'converters.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Decks,
    Cards,
    CardStates,
    Reviews,
    Concepts,
    Exercises,
    ExerciseAttempts,
    ProgressionTiers,
    TierProgress,
    QuestionResults,
    Settings,
    ItemSchedules,
    SessionTemplates,
  ],
  daos: [
    CardsDao,
    DecksDao,
    ReviewsDao,
    ConceptsDao,
    ExercisesDao,
    ProgressionDao,
    QuestionResultsDao,
    SettingsDao,
    ItemSchedulesDao,
    SessionTemplatesDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase()
      : super(driftDatabase(
          name: 'jazz_piano_tools',
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ));
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 15;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) => m.createAll(),
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await m.createTable(progressionTiers);
          await m.createTable(tierProgress);
          await m.createTable(questionResults);
          await m.createTable(settings);
        }
        if (from < 3) {
          await m.addColumn(settings, settings.contentVersion);
        }
        if (from < 5) {
          await m.addColumn(settings, settings.answerInputMode);
        }
        if (from < 6) {
          await m.createTable(itemSchedules);
        }
        if (from < 7) {
          await m.addColumn(settings, settings.showIntervalHints);
        }
        if (from < 8) {
          await m.addColumn(settings, settings.newCardsPerDay);
          await m.addColumn(itemSchedules, itemSchedules.createdAt);
        }
        if (from < 9) {
          await m.addColumn(settings, settings.srsDesiredRetention);
        }
        if (from < 10) {
          await m.addColumn(itemSchedules, itemSchedules.lastReview);
          await m.addColumn(itemSchedules, itemSchedules.step);
          await m.addColumn(cardStates, cardStates.lastReview);
          await m.addColumn(cardStates, cardStates.step);
        }
        if (from < 11) {
          await m.addColumn(settings, settings.quickStartCount);
          await m.addColumn(settings, settings.lastQuickStartAt);
          await m.addColumn(settings, settings.lastTemplateKey);
          await m.addColumn(settings, settings.lastTemplateUsedAt);
          // createTable uses current schema, so folder/tags/isGlobal
          // columns are included — skip the <12 block to avoid duplicates.
          await m.createTable(sessionTemplates);
        } else if (from < 12) {
          await m.addColumn(sessionTemplates, sessionTemplates.folder);
          await m.addColumn(sessionTemplates, sessionTemplates.tags);
          await m.addColumn(sessionTemplates, sessionTemplates.isGlobal);
        }
        if (from < 13) {
          await m.addColumn(decks, decks.parentId);
        }
        if (from < 14) {
          await m.addColumn(settings, settings.deckDrillCount);
          await m.addColumn(settings, settings.deckHardnessLevel);
        }
        if (from < 15) {
          await m.addColumn(settings, settings.themeMode);
        }
      },
    );
  }
}
