import 'package:drift/drift.dart';

import 'progression_tiers_table.dart';

class TierProgress extends Table {
  TextColumn get tierId =>
      text().references(ProgressionTiers, #id)();
  RealColumn get masteryScore => real().withDefault(const Constant(0.0))();
  IntColumn get totalAttempts => integer().withDefault(const Constant(0))();
  IntColumn get correctAttempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPracticed =>
      dateTime().withDefault(Constant(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)))();
  BoolColumn get isUnlocked => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {tierId};
}
