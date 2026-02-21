import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/concepts_table.dart';

part 'concepts_dao.g.dart';

@DriftAccessor(tables: [Concepts])
class ConceptsDao extends DatabaseAccessor<AppDatabase>
    with _$ConceptsDaoMixin {
  ConceptsDao(super.db);

  Future<List<Concept>> getAllConcepts() => select(concepts).get();

  Future<Concept?> getConceptById(String id) {
    return (select(concepts)..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  Future<void> insertConcept(ConceptsCompanion companion) {
    return into(concepts).insert(companion);
  }

  Future<List<Concept>> searchConcepts(String query) {
    final pattern = '%$query%';
    return (select(concepts)
          ..where(
            (c) => c.title.like(pattern) | c.summary.like(pattern),
          ))
        .get();
  }

  Future<List<Concept>> getConceptsByLevel(int level) {
    return (select(concepts)..where((c) => c.level.equals(level))).get();
  }

  Future<int> getConceptCount() async {
    final count = countAll();
    final query = selectOnly(concepts)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }
}
