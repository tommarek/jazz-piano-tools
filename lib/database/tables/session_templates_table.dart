import 'package:drift/drift.dart';

class SessionTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get exerciseId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get subtitle => text().withDefault(const Constant(''))();
  TextColumn get mode => text()();
  IntColumn get questionCount => integer().nullable()();
  IntColumn get newCardCount => integer().nullable()();
  IntColumn get timeLimitSeconds => integer().nullable()();
  TextColumn get folder => text().nullable()();
  TextColumn get tags => text().nullable()();
  BoolColumn get isGlobal =>
      boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
