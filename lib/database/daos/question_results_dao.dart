import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/question_results_table.dart';
import '../tables/exercise_attempts_table.dart';

part 'question_results_dao.g.dart';

@DriftAccessor(tables: [QuestionResults, ExerciseAttempts])
class QuestionResultsDao extends DatabaseAccessor<AppDatabase>
    with _$QuestionResultsDaoMixin {
  QuestionResultsDao(super.db);

  Future<void> insertResult(QuestionResultsCompanion entry) {
    return into(questionResults).insert(entry);
  }

  Future<List<QuestionResult>> getByAttempt(String attemptId) {
    return (select(questionResults)
          ..where((r) => r.attemptId.equals(attemptId)))
        .get();
  }

  /// Per-item accuracy: returns all results for a given topic.
  Future<List<QuestionResult>> getByTopic(String topic) {
    return (select(questionResults)..where((r) => r.topic.equals(topic))).get();
  }

  /// Results within a date range for trend analysis.
  /// Joins through exerciseAttempts to filter by timestamp.
  Future<List<QuestionResult>> getByTopicAndDateRange(
    String topic,
    DateTime start,
    DateTime end,
  ) async {
    final query = select(questionResults).join([
      innerJoin(
        exerciseAttempts,
        exerciseAttempts.id.equalsExp(questionResults.attemptId),
      ),
    ])
      ..where(questionResults.topic.equals(topic) &
          exerciseAttempts.timestamp.isBiggerOrEqualValue(start) &
          exerciseAttempts.timestamp.isSmallerOrEqualValue(end));

    final rows = await query.get();
    return rows.map((row) => row.readTable(questionResults)).toList();
  }
}
