import 'package:drift/drift.dart';

import '../converters.dart';

class Exercises extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get mode => text()();
  TextColumn get inputType => text()();
  TextColumn get generatorId => text()();
  TextColumn get config => text().map(const JsonMapConverter())();
  TextColumn get acceptanceRules => text().map(const JsonMapConverter())();
  TextColumn get scoringRules => text().map(const JsonMapConverter())();
  TextColumn get tags => text().map(const JsonListConverter())();
  IntColumn get level => integer()();
  IntColumn get estimatedMinutes => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
