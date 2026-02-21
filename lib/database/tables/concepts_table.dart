import 'package:drift/drift.dart';

import '../converters.dart';

class Concepts extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get summary => text()();
  TextColumn get bodyMarkdown => text()();
  TextColumn get examples => text().map(const JsonListConverter())();
  TextColumn get tags => text().map(const JsonListConverter())();
  IntColumn get level => integer()();
  TextColumn get relatedExerciseIds =>
      text().map(const JsonListConverter())();
  TextColumn get relatedCardDeckIds =>
      text().map(const JsonListConverter())();

  @override
  Set<Column> get primaryKey => {id};
}
