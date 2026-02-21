import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/providers.dart';
import '../fsrs_adapter.dart';
import '../srs_engine.dart';

part 'srs_provider.g.dart';

@Riverpod(keepAlive: true)
FsrsAdapter fsrsAdapter(FsrsAdapterRef ref) {
  return FsrsAdapter();
}

@Riverpod(keepAlive: true)
SrsEngine srsEngine(SrsEngineRef ref) {
  final db = ref.watch(appDatabaseProvider);
  final adapter = ref.watch(fsrsAdapterProvider);
  return SrsEngine(db, adapter);
}

@riverpod
Future<List<String>> dueCardIds(DueCardIdsRef ref) async {
  final engine = ref.watch(srsEngineProvider);
  return engine.getDueCardIds();
}

@riverpod
Future<int> dueCardCount(DueCardCountRef ref) async {
  final ids = await ref.watch(dueCardIdsProvider.future);
  return ids.length;
}
