import 'package:drift/drift.dart';

import '../converters.dart';
import 'decks_table.dart';

class Cards extends Table {
  TextColumn get id => text()();
  TextColumn get deckId => text().references(Decks, #id)();
  TextColumn get prompt => text()();
  TextColumn get expectedAnswer => text()();
  TextColumn get answerType => text()();
  TextColumn get metadata => text().map(const JsonMapConverter())();

  @override
  Set<Column> get primaryKey => {id};
}
