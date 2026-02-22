import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/progression_tiers_table.dart';
import '../tables/tier_progress_table.dart';

part 'progression_dao.g.dart';

@DriftAccessor(tables: [ProgressionTiers, TierProgress])
class ProgressionDao extends DatabaseAccessor<AppDatabase>
    with _$ProgressionDaoMixin {
  ProgressionDao(super.db);

  Future<List<ProgressionTier>> getTiersByTopic(String topic) {
    return (select(progressionTiers)
          ..where((t) => t.topic.equals(topic))
          ..orderBy([(t) => OrderingTerm.asc(t.tierNumber)]))
        .get();
  }

  Future<List<ProgressionTier>> getAllTiers() {
    return (select(progressionTiers)
          ..orderBy([
            (t) => OrderingTerm.asc(t.topic),
            (t) => OrderingTerm.asc(t.tierNumber),
          ]))
        .get();
  }

  Future<TierProgressData?> getTierProgress(String tierId) {
    return (select(tierProgress)..where((t) => t.tierId.equals(tierId)))
        .getSingleOrNull();
  }

  Future<List<TierProgressData>> getAllProgress() {
    return select(tierProgress).get();
  }

  Future<void> upsertProgress(TierProgressCompanion entry) {
    return into(tierProgress).insertOnConflictUpdate(entry);
  }
}
