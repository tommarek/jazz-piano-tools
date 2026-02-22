import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/providers.dart';
import '../../../database/app_database.dart';

part 'session_templates_provider.g.dart';

@riverpod
Stream<List<SessionTemplate>> sessionTemplates(
  SessionTemplatesRef ref,
  String exerciseId,
) {
  final db = ref.watch(appDatabaseProvider);
  return db.sessionTemplatesDao.watchTemplates(exerciseId);
}
