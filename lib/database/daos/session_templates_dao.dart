import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/session_templates_table.dart';

part 'session_templates_dao.g.dart';

@DriftAccessor(tables: [SessionTemplates])
class SessionTemplatesDao extends DatabaseAccessor<AppDatabase>
    with _$SessionTemplatesDaoMixin {
  SessionTemplatesDao(super.db);

  Stream<List<SessionTemplate>> watchTemplates(String exerciseId) {
    return (select(sessionTemplates)
          ..where((t) =>
              t.exerciseId.equals(exerciseId) | t.isGlobal.equals(true))
          ..orderBy([
            (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<void> upsertTemplate(SessionTemplatesCompanion entry) {
    return into(sessionTemplates).insertOnConflictUpdate(entry);
  }

  Future<void> deleteTemplate(String id) {
    return (delete(sessionTemplates)..where((t) => t.id.equals(id))).go();
  }
}
