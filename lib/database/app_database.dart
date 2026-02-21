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

import 'daos/cards_dao.dart';
import 'daos/decks_dao.dart';
import 'daos/reviews_dao.dart';
import 'daos/concepts_dao.dart';
import 'daos/exercises_dao.dart';

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
  ],
  daos: [
    CardsDao,
    DecksDao,
    ReviewsDao,
    ConceptsDao,
    ExercisesDao,
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
  int get schemaVersion => 1;
}
