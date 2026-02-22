import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/providers.dart';
import '../../domain/enums/exercise_mode.dart';
import '../../domain/enums/input_type.dart';
import '../../domain/models/models.dart' as domain;
import '../../features/srs/providers/srs_provider.dart';
import '../content_loader.dart';
import '../content_repository.dart';

part 'content_providers.g.dart';

@Riverpod(keepAlive: true)
ContentLoader contentLoader(ContentLoaderRef ref) {
  return ContentLoader();
}

@Riverpod(keepAlive: true)
ContentRepository contentRepository(ContentRepositoryRef ref) {
  final db = ref.watch(appDatabaseProvider);
  final loader = ref.watch(contentLoaderProvider);
  return ContentRepository(db, loader);
}

final contentBootstrapProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(contentRepositoryProvider);
  await repo.ensureContentLoaded();

  // Initialize SRS retention from saved settings.
  final db = ref.read(appDatabaseProvider);
  final settings = await db.settingsDao.getSettings();
  if (settings != null) {
    ref.read(srsRetentionProvider.notifier).set(settings.srsDesiredRetention);
  }
});

@riverpod
Future<List<domain.Concept>> allConcepts(AllConceptsRef ref) async {
  final db = ref.watch(appDatabaseProvider);
  final rows = await db.conceptsDao.getAllConcepts();
  return rows
      .map(
        (r) => domain.Concept(
          id: r.id,
          title: r.title,
          summary: r.summary,
          bodyMarkdown: r.bodyMarkdown,
          examples: r.examples
              .map((e) => jsonDecode(e) as Map<String, dynamic>)
              .toList(),
          tags: r.tags,
          level: r.level,
          relatedExerciseIds: r.relatedExerciseIds,
          relatedCardDeckIds: r.relatedCardDeckIds,
        ),
      )
      .toList();
}

@riverpod
Future<List<domain.Exercise>> allExercises(AllExercisesRef ref) async {
  final db = ref.watch(appDatabaseProvider);
  final rows = await db.exercisesDao.getAllExercises();
  return rows
      .map(
        (r) => domain.Exercise(
          id: r.id,
          title: r.title,
          mode: ExerciseMode.values.byName(r.mode),
          inputType: InputType.values.byName(r.inputType),
          generatorId: r.generatorId,
          config: r.config,
          acceptanceRules: r.acceptanceRules,
          scoringRules: r.scoringRules,
          tags: r.tags,
          level: r.level,
          estimatedMinutes: r.estimatedMinutes,
        ),
      )
      .toList();
}

@riverpod
Future<List<domain.Deck>> allDecks(AllDecksRef ref) async {
  final db = ref.watch(appDatabaseProvider);
  final rows = await db.decksDao.getAllDecks();
  return rows
      .map(
        (r) => domain.Deck(
          id: r.id,
          title: r.title,
          tags: r.tags,
          sourceConceptId: r.sourceConceptId,
        ),
      )
      .toList();
}
