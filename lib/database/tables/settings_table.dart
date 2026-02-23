import 'package:drift/drift.dart';
import '../../core/constants/srs_defaults.dart';

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
  /// Theme mode: 'system', 'light', or 'dark'.
  TextColumn get themeMode =>
      text().withDefault(const Constant('system'))();

  /// Whether to show SRS interval hints below rating buttons.
  BoolColumn get showIntervalHints =>
      boolean().withDefault(const Constant(true))();

  /// Maximum number of new (unseen) cards to introduce per day.
  IntColumn get newCardsPerDay =>
      integer().withDefault(const Constant(kDefaultNewCardsPerDay))();

  /// Maximum number of review cards to study per day.
  IntColumn get reviewCardsPerDay =>
      integer().withDefault(const Constant(kDefaultReviewCardsPerDay))();

  /// Learning/relearning cards due within this many minutes can be shown early.
  IntColumn get learnAheadMinutes =>
      integer().withDefault(const Constant(kDefaultLearnAheadMinutes))();

  /// Hour of day when the study day rolls over (0-23), local time.
  IntColumn get dayRolloverHour =>
      integer().withDefault(const Constant(kDefaultDayRolloverHour))();

  /// Comma-separated learning steps in minutes (e.g. "1,10").
  TextColumn get learningStepsMinutes =>
      text().withDefault(const Constant(kDefaultLearningStepsMinutes))();

  /// Comma-separated relearning steps in minutes (e.g. "10").
  TextColumn get relearningStepsMinutes =>
      text().withDefault(const Constant(kDefaultRelearningStepsMinutes))();

  /// First review interval (days) after passing the final learning step with Good.
  IntColumn get graduatingIntervalDays =>
      integer().withDefault(const Constant(kDefaultGraduatingIntervalDays))();

  /// First review interval (days) when answering Easy during learning/relearning.
  IntColumn get easyIntervalDays =>
      integer().withDefault(const Constant(kDefaultEasyIntervalDays))();

  /// Desired retention rate for SRS scheduling (0.0–1.0).
  RealColumn get srsDesiredRetention =>
      real().withDefault(const Constant(kDefaultSrsDesiredRetention))();

  /// Quick start usage count.
  IntColumn get quickStartCount =>
      integer().withDefault(const Constant(0))();

  /// Last quick start timestamp (milliseconds since epoch).
  IntColumn get lastQuickStartAt => integer().nullable()();

  /// Last used template key (builtin or custom id).
  TextColumn get lastTemplateKey => text().nullable()();

  /// Last template usage timestamp (milliseconds since epoch).
  IntColumn get lastTemplateUsedAt => integer().nullable()();

  /// Default card count for deck drill sessions.
  IntColumn get deckDrillCount =>
      integer().withDefault(const Constant(10))();

  /// Hardness level for deck drill (strict, medium, wide).
  TextColumn get deckHardnessLevel =>
      text().withDefault(const Constant('medium'))();

  @override
  Set<Column> get primaryKey => {id};
}
