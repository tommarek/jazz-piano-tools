import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/providers.dart';
import '../progression_service.dart';

part 'progression_provider.g.dart';

@Riverpod(keepAlive: true)
ProgressionService progressionService(ProgressionServiceRef ref) {
  final db = ref.watch(appDatabaseProvider);
  return ProgressionService(db);
}

@riverpod
Future<List<TierWithProgress>> tiersByTopic(
  TiersByTopicRef ref,
  String topic,
) async {
  final service = ref.watch(progressionServiceProvider);
  return service.getTiersForTopic(topic);
}
