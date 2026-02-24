import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/daily_completions_table.dart';

part 'daily_completions_dao.g.dart';

@DriftAccessor(tables: [DailyCompletions])
class DailyCompletionsDao extends DatabaseAccessor<AppDatabase>
    with _$DailyCompletionsDaoMixin {
  DailyCompletionsDao(super.db);

  Future<void> upsertCompletion({
    required String studyDayKey,
    required String category,
    required DateTime completedAt,
  }) {
    return into(dailyCompletions).insertOnConflictUpdate(
      DailyCompletionsCompanion.insert(
        studyDayKey: studyDayKey,
        category: category,
        completedAt: completedAt,
      ),
    );
  }

  Future<List<DailyCompletion>> getAllCompletions() => select(dailyCompletions).get();

  Future<bool> hasCompletionForDay(String studyDayKey) async {
    final row = await (select(dailyCompletions)
          ..where((d) => d.studyDayKey.equals(studyDayKey))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }
}
