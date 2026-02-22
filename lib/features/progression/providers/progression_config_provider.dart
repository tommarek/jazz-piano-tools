import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/providers.dart';
import '../progression_config_resolver.dart';

part 'progression_config_provider.g.dart';

@Riverpod(keepAlive: true)
ProgressionConfigResolver progressionConfigResolver(
  ProgressionConfigResolverRef ref,
) {
  final db = ref.watch(appDatabaseProvider);
  return ProgressionConfigResolver(db);
}

@riverpod
Future<Map<String, dynamic>> unlockedConfig(
  UnlockedConfigRef ref,
  String topic,
) async {
  final resolver = ref.watch(progressionConfigResolverProvider);
  return resolver.getUnlockedConfig(topic);
}
