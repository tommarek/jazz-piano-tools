import 'package:drift/drift.dart';

class DailyCompletions extends Table {
  TextColumn get studyDayKey => text()();
  TextColumn get category => text()();
  DateTimeColumn get completedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {studyDayKey, category};
}
