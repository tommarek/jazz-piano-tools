import 'package:drift/drift.dart';

import '../converters.dart';

class ProgressionTiers extends Table {
  TextColumn get id => text()();
  TextColumn get topic => text()();
  IntColumn get tierNumber => integer()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get config => text().map(const JsonMapConverter())();

  @override
  Set<Column> get primaryKey => {id};
}
