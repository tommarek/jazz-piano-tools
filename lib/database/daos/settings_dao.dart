import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/settings_table.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [Settings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.db);

  Future<Setting?> getSettings() {
    return (select(settings)..where((s) => s.id.equals(1))).getSingleOrNull();
  }

  Future<void> upsertSettings(SettingsCompanion entry) {
    return into(settings).insertOnConflictUpdate(
      entry.copyWith(id: const Value(1)),
    );
  }

  Stream<Setting?> watchSettings() {
    return (select(settings)..where((s) => s.id.equals(1)))
        .watchSingleOrNull();
  }
}
