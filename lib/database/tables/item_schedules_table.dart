import 'package:drift/drift.dart';

class ItemSchedules extends Table {
  TextColumn get topic => text()();
  TextColumn get itemId => text()();
  DateTimeColumn get due => dateTime()();
  RealColumn get stability => real().withDefault(const Constant(0.0))();
  RealColumn get difficulty => real().withDefault(const Constant(0.0))();
  IntColumn get interval => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();
  IntColumn get reps => integer().withDefault(const Constant(0))();
  TextColumn get state => text().withDefault(const Constant('new'))();
  DateTimeColumn get lastReview => dateTime().nullable()();
  IntColumn get step => integer().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {topic, itemId};
}
