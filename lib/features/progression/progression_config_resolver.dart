import '../../database/app_database.dart';

/// Resolves the currently unlocked configuration for a topic by merging
/// all unlocked progression tier configs.
class ProgressionConfigResolver {
  final AppDatabase _db;

  ProgressionConfigResolver(this._db);

  /// Returns merged config from all unlocked tiers for a [topic].
  ///
  /// Merges list fields (`intervals`, `roots`, `qualities`) by union.
  Future<Map<String, dynamic>> getUnlockedConfig(String topic) async {
    final tiers = await _db.progressionDao.getTiersByTopic(topic);
    final allProgress = await _db.progressionDao.getAllProgress();
    final progressMap = {
      for (final p in allProgress) p.tierId: p,
    };

    final mergedIntervals = <int>{};
    final mergedRoots = <int>{};
    final mergedQualities = <String>{};

    for (final tier in tiers) {
      final progress = progressMap[tier.id];
      final isUnlocked =
          progress?.isUnlocked ?? (tier.tierNumber == 1);
      if (!isUnlocked) continue;

      final config = tier.config;
      if (config['intervals'] is List) {
        for (final v in config['intervals'] as List) {
          mergedIntervals.add(v as int);
        }
      }
      if (config['roots'] is List) {
        for (final v in config['roots'] as List) {
          mergedRoots.add(v as int);
        }
      }
      if (config['qualities'] is List) {
        for (final v in config['qualities'] as List) {
          mergedQualities.add(v as String);
        }
      }
    }

    return {
      if (mergedIntervals.isNotEmpty)
        'intervals': mergedIntervals.toList(),
      if (mergedRoots.isNotEmpty)
        'roots': mergedRoots.toList(),
      if (mergedQualities.isNotEmpty)
        'qualities': mergedQualities.toList(),
    };
  }

  /// Maps an itemId and topic to the tier that contains it.
  ///
  /// Searches from the highest tier first so that items appearing in
  /// multiple tiers are attributed to the most advanced one.
  /// Returns the tier ID if found, null otherwise.
  Future<String?> findTierForItem(
    String topic,
    String itemId,
    int? semitones,
  ) async {
    final tiers = await _db.progressionDao.getTiersByTopic(topic);

    // Iterate in reverse (highest tier number first) so overlapping
    // items are attributed to the most advanced tier.
    for (final tier in tiers.reversed) {
      final config = tier.config;

      // Check intervals
      if (semitones != null && config['intervals'] is List) {
        final intervals = (config['intervals'] as List).cast<int>();
        if (intervals.contains(semitones)) return tier.id;
      }

      // Check qualities
      if (config['qualities'] is List) {
        final qualities = (config['qualities'] as List).cast<String>();
        if (qualities.contains(itemId)) return tier.id;
      }
    }

    return null;
  }
}
