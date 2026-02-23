import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/providers.dart';
import '../../../core/constants/refresh_intervals.dart';
import '../../../core/constants/srs_defaults.dart';
import '../../../database/app_database.dart';
import '../fsrs_adapter.dart';
import '../srs_engine.dart';

part 'srs_provider.g.dart';

@riverpod
Stream<int> dueRefreshTicker(DueRefreshTickerRef ref) async* {
  var tick = 0;
  yield tick;
  while (true) {
    await Future<void>.delayed(kFastCountRefreshInterval);
    yield ++tick;
  }
}

@Riverpod(keepAlive: true)
class SrsRetention extends _$SrsRetention {
  @override
  double build() {
    // The actual value is loaded asynchronously by the content bootstrap
    // provider, which calls set() before any reviews can happen.
    return kDefaultSrsDesiredRetention;
  }

  void set(double value) {
    state = value;
  }

  Future<void> save(double value) async {
    state = value;
    final db = ref.read(appDatabaseProvider);
    await db.settingsDao.upsertSettings(
      SettingsCompanion(srsDesiredRetention: Value(value)),
    );
  }
}

@Riverpod(keepAlive: true)
FsrsAdapter fsrsAdapter(FsrsAdapterRef ref) {
  final retention = ref.watch(srsRetentionProvider);
  return FsrsAdapter(desiredRetention: retention);
}

@Riverpod(keepAlive: true)
SrsEngine srsEngine(SrsEngineRef ref) {
  final db = ref.watch(appDatabaseProvider);
  final adapter = ref.watch(fsrsAdapterProvider);
  return SrsEngine(db, adapter);
}

@riverpod
Future<List<String>> dueCardIds(DueCardIdsRef ref) async {
  // Recompute due cards periodically so cards that become due over time
  // appear without requiring a write/invalidation event.
  ref.watch(dueRefreshTickerProvider);
  final engine = ref.watch(srsEngineProvider);
  return engine.getDueCardIds();
}

@riverpod
Future<int> dueCardCount(DueCardCountRef ref) async {
  final ids = await ref.watch(dueCardIdsProvider.future);
  return ids.length;
}
