import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/exercises_table.dart';
import '../tables/exercise_attempts_table.dart';

part 'exercises_dao.g.dart';

@DriftAccessor(tables: [Exercises, ExerciseAttempts])
class ExercisesDao extends DatabaseAccessor<AppDatabase>
    with _$ExercisesDaoMixin {
  ExercisesDao(super.db);

  Future<List<Exercise>> getAllExercises() => select(exercises).get();

  Future<Exercise?> getExerciseById(String id) {
    return (select(exercises)..where((e) => e.id.equals(id))).getSingleOrNull();
  }

  Future<void> insertExercise(ExercisesCompanion companion) {
    return into(exercises).insert(companion);
  }

  Future<List<Exercise>> getExercisesByMode(String mode) {
    return (select(exercises)..where((e) => e.mode.equals(mode))).get();
  }

  Future<void> insertAttempt(ExerciseAttemptsCompanion companion) {
    return into(exerciseAttempts).insert(companion);
  }

  Future<List<ExerciseAttempt>> getAttemptsForExercise(String exerciseId) {
    return (select(exerciseAttempts)
          ..where((a) => a.exerciseId.equals(exerciseId)))
        .get();
  }
}
