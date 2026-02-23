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

  /// Timestamps of attempts with at least one answered question.
  /// Uses question_results join so opening/quitting a session does not count.
  Future<List<DateTime>> getAnsweredAttemptTimestamps() async {
    final rows = await customSelect(
      '''
      SELECT DISTINCT a.timestamp AS ts
      FROM question_results q
      INNER JOIN exercise_attempts a ON a.id = q.attempt_id
      ''',
      readsFrom: {questionResults, exerciseAttempts},
    ).get();
    return rows.map((r) => r.read<DateTime>('ts')).toList();
  }
}
