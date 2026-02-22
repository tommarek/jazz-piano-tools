import 'package:drift/drift.dart';

import '../../database/app_database.dart';

/// Manages progression tier mastery and unlock logic.
class ProgressionService {
  final AppDatabase _db;

  static const _masteryThreshold = 0.80;
  static const _minAttempts = 20;

  ProgressionService(this._db);

  /// Gets all tiers for a topic, paired with their progress.
  Future<List<TierWithProgress>> getTiersForTopic(String topic) async {
    final tiers = await _db.progressionDao.getTiersByTopic(topic);
    final allProgress = await _db.progressionDao.getAllProgress();
    final progressMap = {
      for (final p in allProgress) p.tierId: p,
    };

    return tiers.map((tier) {
      return TierWithProgress(
        tier: tier,
        progress: progressMap[tier.id],
      );
    }).toList();
  }

  /// Records an attempt and updates tier progress.
  Future<void> recordAttempt(
    String tierId, {
    required bool correct,
  }) async {
    final existing = await _db.progressionDao.getTierProgress(tierId);

    final totalAttempts = (existing?.totalAttempts ?? 0) + 1;
    final correctAttempts = (existing?.correctAttempts ?? 0) + (correct ? 1 : 0);
    final mastery = totalAttempts > 0 ? correctAttempts / totalAttempts : 0.0;

    await _db.progressionDao.upsertProgress(
      TierProgressCompanion(
        tierId: Value(tierId),
        masteryScore: Value(mastery),
        totalAttempts: Value(totalAttempts),
        correctAttempts: Value(correctAttempts),
        lastPracticed: Value(DateTime.now()),
        isUnlocked: Value(existing?.isUnlocked ?? true),
      ),
    );

    // Check if next tier should be unlocked
    await _checkUnlocks(tierId);
  }

  /// Checks if a tier's mastery qualifies unlocking the next tier.
  Future<void> _checkUnlocks(String tierId) async {
    final progress = await _db.progressionDao.getTierProgress(tierId);
    if (progress == null) return;

    if (progress.masteryScore >= _masteryThreshold &&
        progress.totalAttempts >= _minAttempts) {
      // Find the tier to get its topic and number
      final allTiers = await _db.progressionDao.getAllTiers();
      final currentTier = allTiers.where((t) => t.id == tierId).firstOrNull;
      if (currentTier == null) return;

      // Find next tier in same topic
      final nextTier = allTiers
          .where((t) =>
              t.topic == currentTier.topic &&
              t.tierNumber == currentTier.tierNumber + 1)
          .firstOrNull;

      if (nextTier != null) {
        final nextProgress =
            await _db.progressionDao.getTierProgress(nextTier.id);
        if (nextProgress == null || !nextProgress.isUnlocked) {
          await _db.progressionDao.upsertProgress(
            TierProgressCompanion(
              tierId: Value(nextTier.id),
              isUnlocked: const Value(true),
              masteryScore: Value(nextProgress?.masteryScore ?? 0.0),
              totalAttempts: Value(nextProgress?.totalAttempts ?? 0),
              correctAttempts: Value(nextProgress?.correctAttempts ?? 0),
              lastPracticed: Value(
                nextProgress?.lastPracticed ??
                    DateTime.fromMillisecondsSinceEpoch(0),
              ),
            ),
          );
        }
      }
    }
  }

  /// Computes a mastery level label from accuracy and attempts.
  static String masteryLevel(double accuracy, int attempts) {
    if (attempts < 5) return 'New';
    if (accuracy >= 0.95) return 'Mastered';
    if (accuracy >= 0.80) return 'Proficient';
    if (accuracy >= 0.60) return 'Developing';
    return 'Beginner';
  }
}

class TierWithProgress {
  final ProgressionTier tier;
  final TierProgressData? progress;

  const TierWithProgress({required this.tier, this.progress});

  double get mastery => progress?.masteryScore ?? 0.0;
  int get attempts => progress?.totalAttempts ?? 0;
  bool get isUnlocked => progress?.isUnlocked ?? tier.tierNumber == 1;
}
