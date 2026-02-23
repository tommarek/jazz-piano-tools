import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/providers.dart';
import '../../../content/providers/content_providers.dart';
import '../../../core/constants/refresh_intervals.dart';
import '../../../core/constants/srs_defaults.dart';
import '../../../domain/models/exercise.dart';
import '../../drill/generators/generator_registry.dart';
import '../../srs/providers/srs_provider.dart';

part 'today_session_provider.g.dart';

class ExerciseWithCounts {
  final Exercise exercise;
  final int reviewCount;
  final int newCount;

  const ExerciseWithCounts({
    required this.exercise,
    this.reviewCount = 0,
    this.newCount = 0,
  });

  int get totalDue => reviewCount + newCount;
}

class TodaySessionState {
  final int dueCardCount;
  final int learningDueCount;
  final int reviewDueCount;
  final int newCardsRemaining;
  final int completedReviews;
  final List<ExerciseWithCounts> exercises;
  final int sessionEstimateMinutes;

  const TodaySessionState({
    this.dueCardCount = 0,
    this.learningDueCount = 0,
    this.reviewDueCount = 0,
    this.newCardsRemaining = 0,
    this.completedReviews = 0,
    this.exercises = const [],
    this.sessionEstimateMinutes = 0,
  });

  TodaySessionState copyWith({
    int? dueCardCount,
    int? learningDueCount,
    int? reviewDueCount,
    int? newCardsRemaining,
    int? completedReviews,
    List<ExerciseWithCounts>? exercises,
    int? sessionEstimateMinutes,
  }) {
    return TodaySessionState(
      dueCardCount: dueCardCount ?? this.dueCardCount,
      learningDueCount: learningDueCount ?? this.learningDueCount,
      reviewDueCount: reviewDueCount ?? this.reviewDueCount,
      newCardsRemaining: newCardsRemaining ?? this.newCardsRemaining,
      completedReviews: completedReviews ?? this.completedReviews,
      exercises: exercises ?? this.exercises,
      sessionEstimateMinutes:
          sessionEstimateMinutes ?? this.sessionEstimateMinutes,
    );
  }
}

@riverpod
Future<TodaySessionState> todaySession(TodaySessionRef ref) async {
  final allExercises = await ref.watch(allExercisesProvider.future);
  final db = ref.watch(appDatabaseProvider);
  final engine = ref.watch(srsEngineProvider);
  final queueStats = await engine.getQueueStats();
  final dueCount = queueStats.totalDue;

  final now = DateTime.now();
  final settings = await db.settingsDao.getSettings();
  final newCardsPerDay = settings?.newCardsPerDay ?? kDefaultNewCardsPerDay;
  final newCardsRemainingToday = queueStats.newAvailableToday;

  // Cache per-topic data to avoid duplicate queries for exercises sharing a topic
  final topicScheduledIds = <String, Set<String>>{};
  final topicDueIds = <String, List<String>>{};

  Future<Set<String>> getScheduledIds(String topic) async {
    return topicScheduledIds[topic] ??=
        await db.itemSchedulesDao.getScheduledItemIds(topic);
  }

  Future<List<String>> getDueIds(String topic) async {
    return topicDueIds[topic] ??=
        await db.itemSchedulesDao.getDueItemIds(topic, now);
  }

  // Global new-card budget shared across all topics
  final globalNewIntroducedToday =
      await db.itemSchedulesDao.getNewItemsIntroducedTodayGlobal();
  var remainingNewSlots = (newCardsPerDay - globalNewIntroducedToday).clamp(0, newCardsPerDay);

  // Build exercise list with counts
  final exercisesWithCounts = <ExerciseWithCounts>[];

  for (final exercise in allExercises) {
    final topic = topicForGenerator(exercise.generatorId);
    if (topic == null) {
      exercisesWithCounts.add(ExerciseWithCounts(exercise: exercise));
      continue;
    }

    final generator = resolveGenerator(exercise.generatorId);
    final allIds = generator.allItemIds(exercise);
    final allIdSet = allIds.toSet();

    final scheduledIds = await getScheduledIds(topic);
    final dueIds = await getDueIds(topic);

    final reviewCount =
        dueIds.where((id) => allIdSet.contains(id)).length;
    final availableNew =
        allIds.where((id) => !scheduledIds.contains(id)).length;
    final newSlots = remainingNewSlots.clamp(0, availableNew);
    remainingNewSlots = (remainingNewSlots - newSlots).clamp(0, newCardsPerDay);

    exercisesWithCounts.add(ExerciseWithCounts(
      exercise: exercise,
      reviewCount: reviewCount,
      newCount: newSlots,
    ));
  }

  // Sort: exercises with work first, then alphabetically
  exercisesWithCounts.sort((a, b) {
    if (a.totalDue > 0 && b.totalDue == 0) return -1;
    if (a.totalDue == 0 && b.totalDue > 0) return 1;
    return a.exercise.title.compareTo(b.exercise.title);
  });

  // Estimate time
  final reviewMinutes = (dueCount * 0.5).ceil();
  final exerciseMinutes = exercisesWithCounts.fold<int>(
    0,
    (sum, e) => sum + (e.totalDue > 0 ? e.exercise.estimatedMinutes : 0),
  );
  final totalEstimate = reviewMinutes + exerciseMinutes;

  return TodaySessionState(
    dueCardCount: dueCount,
    learningDueCount: queueStats.learningDue,
    reviewDueCount: queueStats.reviewDue,
    newCardsRemaining: newCardsRemainingToday,
    completedReviews: 0,
    exercises: exercisesWithCounts,
    sessionEstimateMinutes: totalEstimate,
  );
}

class TodayDashboardCounts {
  final int dueCardCount;
  final int learningDueCount;
  final int reviewDueCount;
  final int newCardsRemaining;
  final int estimatedMinutes;

  const TodayDashboardCounts({
    this.dueCardCount = 0,
    this.learningDueCount = 0,
    this.reviewDueCount = 0,
    this.newCardsRemaining = 0,
    this.estimatedMinutes = 0,
  });
}

@riverpod
Stream<TodayDashboardCounts> todayDashboardCounts(
  TodayDashboardCountsRef ref,
) async* {
  final engine = ref.watch(srsEngineProvider);
  while (true) {
    final queueStats = await engine.getQueueStats();
    yield TodayDashboardCounts(
      dueCardCount: queueStats.totalDue,
      learningDueCount: queueStats.learningDue,
      reviewDueCount: queueStats.reviewDue,
      newCardsRemaining: queueStats.newAvailableToday,
      estimatedMinutes: (queueStats.totalDue * 0.5).ceil(),
    );
    await Future<void>.delayed(kFastCountRefreshInterval);
  }
}
