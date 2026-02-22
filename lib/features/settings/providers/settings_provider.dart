import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/providers.dart';
import '../../../database/app_database.dart';

part 'settings_provider.g.dart';

@riverpod
Stream<Setting?> settings(SettingsRef ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.settingsDao.watchSettings();
}
