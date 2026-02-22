import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/item_schedules_table.dart';

part 'item_schedules_dao.g.dart';

@DriftAccessor(tables: [ItemSchedules])
class ItemSchedulesDao extends DatabaseAccessor<AppDatabase>
    with _$ItemSchedulesDaoMixin {
  ItemSchedulesDao(super.db);

  Future<ItemSchedule?> getSchedule(String topic, String itemId) {
    return (select(itemSchedules)
          ..where((r) => r.topic.equals(topic) & r.itemId.equals(itemId)))
        .getSingleOrNull();
  }

  Future<void> upsertSchedule(ItemSchedulesCompanion entry) {
    return into(itemSchedules).insertOnConflictUpdate(entry);
  }

  /// Returns a map of topic -> count of items where due <= [now].
  Future<Map<String, int>> getDueCountByTopic(DateTime now) async {
    final rows = await (select(itemSchedules)
          ..where((r) => r.due.isSmallerOrEqualValue(now)))
        .get();
    final counts = <String, int>{};
    for (final row in rows) {
      counts[row.topic] = (counts[row.topic] ?? 0) + 1;
    }
    return counts;
  }

  /// Returns all items where due <= [now].
  Future<List<ItemSchedule>> getAllDueItems(DateTime now) {
    return (select(itemSchedules)
          ..where((r) => r.due.isSmallerOrEqualValue(now)))
        .get();
  }

  /// Returns all scheduled item IDs for a [topic].
  Future<Set<String>> getScheduledItemIds(String topic) async {
    final rows = await (select(itemSchedules)
          ..where((r) => r.topic.equals(topic)))
        .get();
    return rows.map((r) => r.itemId).toSet();
  }

  /// Returns due item IDs for a [topic] where due <= [now].
  Future<List<String>> getDueItemIds(String topic, DateTime now) async {
    final rows = await (select(itemSchedules)
          ..where(
              (r) => r.topic.equals(topic) & r.due.isSmallerOrEqualValue(now)))
        .get();
    return rows.map((r) => r.itemId).toList();
  }

  /// Returns item IDs with 2+ lapses OR stability <= 2.0 for a [topic],
  /// sorted by stability ascending (weakest first).
  Future<List<String>> getHardItemIds(String topic) async {
    final rows = await (select(itemSchedules)
          ..where((r) =>
              r.topic.equals(topic) &
              (r.lapses.isBiggerOrEqualValue(2) |
                  r.stability.isSmallerOrEqualValue(2.0)))
          ..orderBy([(r) => OrderingTerm.asc(r.stability)]))
        .get();
    return rows.map((r) => r.itemId).toList();
  }

  /// Returns the number of items first introduced today for a [topic].
  ///
  /// Uses the user's local day boundary so the daily new-card limit
  /// resets at local midnight rather than UTC midnight.
  Future<int> getNewItemsIntroducedToday(String topic) async {
    final now = DateTime.now();
    final todayStart = DateTime.utc(now.year, now.month, now.day);
    final rows = await (select(itemSchedules)
          ..where((r) =>
              r.topic.equals(topic) &
              r.createdAt.isBiggerOrEqualValue(todayStart)))
        .get();
    return rows.length;
  }

  /// Returns the total number of new items introduced today across all topics.
  Future<int> getNewItemsIntroducedTodayGlobal() async {
    final now = DateTime.now();
    final todayStart = DateTime.utc(now.year, now.month, now.day);
    final rows = await (select(itemSchedules)
          ..where((r) =>
              r.createdAt.isBiggerOrEqualValue(todayStart)))
        .get();
    return rows.length;
  }
}
