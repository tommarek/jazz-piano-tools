import '../../database/app_database.dart';

/// Provides statistical analysis of user performance.
class StatisticsService {
  final AppDatabase _db;

  StatisticsService(this._db);

  /// Gets per-item accuracy for a topic (e.g., per-interval or per-chord).
  Future<Map<String, ItemStats>> getItemStats(String topic) async {
    final results = await _db.questionResultsDao.getByTopic(topic);
    final stats = <String, ItemStats>{};

    for (final r in results) {
      final existing = stats[r.itemId];
      stats[r.itemId] = ItemStats(
        itemId: r.itemId,
        totalAttempts: (existing?.totalAttempts ?? 0) + 1,
        correctAttempts:
            (existing?.correctAttempts ?? 0) + (r.correct ? 1 : 0),
        totalResponseTimeMs:
            (existing?.totalResponseTimeMs ?? 0) + r.responseTimeMs,
      );
    }

    return stats;
  }

  /// Gets per-key accuracy for a topic.
  Future<Map<int, ItemStats>> getKeyAccuracy(String topic) async {
    final results = await _db.questionResultsDao.getByTopic(topic);
    final stats = <int, ItemStats>{};

    for (final r in results) {
      final key = r.keyRoot;
      if (key == null) continue;
      final existing = stats[key];
      stats[key] = ItemStats(
        itemId: key.toString(),
        totalAttempts: (existing?.totalAttempts ?? 0) + 1,
        correctAttempts:
            (existing?.correctAttempts ?? 0) + (r.correct ? 1 : 0),
        totalResponseTimeMs:
            (existing?.totalResponseTimeMs ?? 0) + r.responseTimeMs,
      );
    }

    return stats;
  }

  /// Computes a mastery level from accuracy and attempt count.
  static String computeMasteryLevel(double accuracy, int attempts) {
    if (attempts < 5) return 'New';
    if (accuracy >= 0.95) return 'Mastered';
    if (accuracy >= 0.80) return 'Proficient';
    if (accuracy >= 0.60) return 'Developing';
    return 'Beginner';
  }
}

class ItemStats {
  final String itemId;
  final int totalAttempts;
  final int correctAttempts;
  final int totalResponseTimeMs;

  const ItemStats({
    required this.itemId,
    this.totalAttempts = 0,
    this.correctAttempts = 0,
    this.totalResponseTimeMs = 0,
  });

  double get accuracy =>
      totalAttempts > 0 ? correctAttempts / totalAttempts : 0.0;

  int get avgResponseTimeMs =>
      totalAttempts > 0 ? totalResponseTimeMs ~/ totalAttempts : 0;

  String get masteryLevel =>
      StatisticsService.computeMasteryLevel(accuracy, totalAttempts);
}
