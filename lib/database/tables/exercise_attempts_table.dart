import 'package:drift/drift.dart';

import '../converters.dart';
import 'exercises_table.dart';

class ExerciseAttempts extends Table {
  TextColumn get id => text()();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  RealColumn get score => real()();
  IntColumn get durationSeconds => integer()();
  TextColumn get key => text().nullable()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get details => text().map(const JsonMapConverter())();

  @override
  Set<Column> get primaryKey => {id};
}
