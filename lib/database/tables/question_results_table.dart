import 'package:drift/drift.dart';

import '../converters.dart';
import 'exercise_attempts_table.dart';

class QuestionResults extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get attemptId => text().references(ExerciseAttempts, #id)();
  IntColumn get questionIndex => integer()();
  BoolColumn get correct => boolean()();
  IntColumn get responseTimeMs => integer()();
  TextColumn get topic => text()();
  TextColumn get skill => text()();
  TextColumn get itemId => text()();
  IntColumn get keyRoot => integer().nullable()();
  TextColumn get metadata => text().map(const JsonMapConverter()).withDefault(const Constant('{}'))();
}
