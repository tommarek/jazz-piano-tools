import 'package:drift/drift.dart';

import 'cards_table.dart';

class CardStates extends Table {
  TextColumn get cardId => text().references(Cards, #id)();
  DateTimeColumn get due => dateTime()();
  RealColumn get stability => real()();
  RealColumn get difficulty => real()();
  IntColumn get interval => integer()();
  IntColumn get lapses => integer()();
  IntColumn get reps => integer()();
  TextColumn get state => text()();
  DateTimeColumn get lastReview => dateTime().nullable()();
  IntColumn get step => integer().nullable()();

  @override
  Set<Column> get primaryKey => {cardId};
}
