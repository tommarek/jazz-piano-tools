import 'package:drift/drift.dart';

class Settings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get noteDisplayStyle =>
      text().withDefault(const Constant('auto'))();
  BoolColumn get showNotation =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get autoPlayAudio =>
      boolean().withDefault(const Constant(false))();
  IntColumn get questionsPerSession =>
      integer().withDefault(const Constant(10))();
  IntColumn get drillTimeLimitSeconds =>
      integer().withDefault(const Constant(120))();
  IntColumn get contentVersion =>
      integer().withDefault(const Constant(0))();
  /// Answer input mode: 'multipleChoice', 'keyboard', or 'none'.
  TextColumn get answerInputMode =>
      text().withDefault(const Constant('keyboard'))();

  /// Whether to show SRS interval hints below rating buttons.
  BoolColumn get showIntervalHints =>
      boolean().withDefault(const Constant(true))();

  /// Maximum number of new (unseen) cards to introduce per day.
  IntColumn get newCardsPerDay =>
      integer().withDefault(const Constant(5))();

  /// Desired retention rate for SRS scheduling (0.0–1.0).
  RealColumn get srsDesiredRetention =>
      real().withDefault(const Constant(0.9))();

  @override
  Set<Column> get primaryKey => {id};
}
