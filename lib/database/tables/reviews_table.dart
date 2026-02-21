import 'package:drift/drift.dart';

import 'cards_table.dart';

class Reviews extends Table {
  TextColumn get id => text()();
  TextColumn get cardId => text().references(Cards, #id)();
  DateTimeColumn get timestamp => dateTime()();
  IntColumn get rating => integer()();
  IntColumn get responseTimeMs => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
