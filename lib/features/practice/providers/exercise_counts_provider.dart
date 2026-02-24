import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/providers.dart';
import '../../../content/providers/content_providers.dart';
import '../../drill/generators/generator_registry.dart';

part 'exercise_counts_provider.g.dart';

class ExerciseCounts {
  final int reviewCount;
  final int newCount;
  final int availableNew;
  final int learnedCount;
  const ExerciseCounts({this.reviewCount = 0, this.newCount = 0, this.availableNew = 0, this.learnedCount = 0});
}

class GroupCounts {
  final String groupName;
  final int totalItems;
  final int dueCount;
  final int newCount;
  final int learnedCount;

  const GroupCounts({
    required this.groupName,
    this.totalItems = 0,
    this.dueCount = 0,
    this.newCount = 0,
    this.learnedCount = 0,
  });
}

@riverpod
Future<ExerciseCounts> exerciseCounts(
    ExerciseCountsRef ref, String exerciseId) async {
  final exercises = await ref.watch(allExercisesProvider.future);
  final exercise = exercises.where((e) => e.id == exerciseId).firstOrNull;
  if (exercise == null) return const ExerciseCounts();

  final topic = topicForGenerator(exercise.generatorId);
  if (topic == null) return const ExerciseCounts();

  final db = ref.watch(appDatabaseProvider);
  final settings = await db.settingsDao.getSettings();
  final newCardsPerDay = settings?.newCardsPerDay ?? 5;
  final now = DateTime.now();

  final generator = resolveGenerator(exercise.generatorId);
  final allIds = generator.allItemIds(exercise);
  final allIdSet = allIds.toSet();

  final scheduledIds = await db.itemSchedulesDao.getScheduledItemIds(topic);
  final dueIds = await db.itemSchedulesDao.getDueItemIds(topic, now);
  final newIntroducedToday =
      await db.itemSchedulesDao.getNewItemsIntroducedToday(topic);

  final reviewCount = dueIds.where((id) => allIdSet.contains(id)).length;
  final availableNew = allIds.where((id) => !scheduledIds.contains(id)).length;
  final newSlots = (newCardsPerDay - newIntroducedToday).clamp(0, availableNew);

  final learnedCount = scheduledIds.where((id) => allIdSet.contains(id)).length;

  return ExerciseCounts(reviewCount: reviewCount, newCount: newSlots, availableNew: availableNew, learnedCount: learnedCount);
}

@riverpod
Future<List<GroupCounts>> exerciseGroupCounts(
    ExerciseGroupCountsRef ref, String exerciseId) async {
  final exercises = await ref.watch(allExercisesProvider.future);
  final exercise = exercises.where((e) => e.id == exerciseId).firstOrNull;
  if (exercise == null) return const [];

  final topic = topicForGenerator(exercise.generatorId);
  if (topic == null) return const [];

  final db = ref.watch(appDatabaseProvider);
  final now = DateTime.now();

  final generator = resolveGenerator(exercise.generatorId);
  final groups = generator.itemGroups(exercise);

  final scheduledIds = await db.itemSchedulesDao.getScheduledItemIds(topic);
  final dueIds = (await db.itemSchedulesDao.getDueItemIds(topic, now)).toSet();

  final result = <GroupCounts>[];
  for (final entry in groups.entries) {
    final groupIds = entry.value;
    final groupIdSet = groupIds.toSet();
    final due = dueIds.where((id) => groupIdSet.contains(id)).length;
    final learned = scheduledIds.where((id) => groupIdSet.contains(id)).length;
    final newCount = groupIds.where((id) => !scheduledIds.contains(id)).length;

    result.add(GroupCounts(
      groupName: entry.key,
      totalItems: groupIds.length,
      dueCount: due,
      newCount: newCount,
      learnedCount: learned,
    ));
  }
  return result;
}
