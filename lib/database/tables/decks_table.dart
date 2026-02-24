import 'package:drift/drift.dart';

import '../converters.dart';

class Decks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get tags => text().map(const JsonListConverter())();
  TextColumn get sourceConceptId => text().nullable()();
  TextColumn get parentId => text().nullable()();
  BoolColumn get excludeFromDailyReview =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
