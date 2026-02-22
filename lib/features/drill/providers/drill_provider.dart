import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../content/providers/content_providers.dart';
import '../../../database/app_database.dart' hide Exercise;
import '../../../domain/models/exercise.dart';
import '../../../domain/models/srs_card_state.dart';
import '../../progression/providers/progression_config_provider.dart';
import '../../progression/providers/progression_provider.dart';
import '../../srs/providers/srs_provider.dart';
import '../generators/generator_registry.dart';
import '../runner/exercise_question.dart';

part 'drill_provider.g.dart';

@riverpod
Future<Exercise> exerciseById(ExerciseByIdRef ref, String exerciseId) async {
  final exercises = await ref.watch(allExercisesProvider.future);
  return exercises.firstWhere((e) => e.id == exerciseId);
}

enum DrillPhase { prompt, input, feedback, complete }

@riverpod
class DrillSession extends _$DrillSession {
  @override
  DrillSessionState build(String exerciseId) {
    return const DrillSessionState();
  }

  Future<void> startDrill({
    required int totalQuestions,
    required int timeLimitSeconds,
    required Exercise exercise,
    Set<String>? selectedGroups,
  }) async {
    // Resolve progression config for "all" values
    final resolvedExercise = await _resolveConfig(exercise);

    final generator = resolveGenerator(resolvedExercise.generatorId);
    List<ExerciseQuestion> questions;
    if (selectedGroups != null && selectedGroups.isNotEmpty) {
      final groups = generator.itemGroups(resolvedExercise);
      final itemIds = groups.entries
          .where((e) => selectedGroups.contains(e.key))
          .expand((e) => e.value)
          .toList()
        ..shuffle();
      final targetIds = itemIds.take(totalQuestions).toList();
      questions = generator.generateForItems(resolvedExercise, targetIds);
      questions.shuffle();
    } else {
      questions = generator.generate(resolvedExercise, count: totalQuestions);
    }

    if (questions.isEmpty) {
      state = const DrillSessionState(phase: DrillPhase.complete);
      return;
    }

    final attemptId = const Uuid().v4();

    // Insert attempt row
    final db = ref.read(appDatabaseProvider);
    await db.exercisesDao.insertAttempt(ExerciseAttemptsCompanion.insert(
      id: attemptId,
      exerciseId: exercise.id,
      score: 0.0,
      durationSeconds: 0,
      timestamp: DateTime.now(),
      details: {},
    ));

    state = DrillSessionState(
      phase: DrillPhase.prompt,
      totalQuestions: questions.length,
      timeLimitSeconds: timeLimitSeconds,
      currentQuestionIndex: 0,
      correctCount: 0,
      startTime: DateTime.now(),
      questions: questions,
      attemptId: attemptId,
      exerciseId: exercise.id,
    );
  }

  /// Starts a practice session driven by SRS: due reviews + new items up to
  /// the daily limit. Returns the number of questions (0 = nothing to do).
  ///
  /// When [selectedGroups] is set, only items belonging to those groups are
  /// included. When [ignoreNewCardLimit] is true, the daily new-card cap
  /// is bypassed (used for "Learn More"). When [newCardCount] is set, that
  /// exact number of new cards is used instead of the daily cap.
  /// When [learnedOnly] is true, all previously scheduled items are included
  /// regardless of due date (for drilling already-learned cards).
  Future<int> startPracticeSession({
    required Exercise exercise,
    Set<String>? selectedGroups,
    bool ignoreNewCardLimit = false,
    int? newCardCount,
    bool learnedOnly = false,
  }) async {
    final resolvedExercise = await _resolveConfig(exercise);
    final generator = resolveGenerator(resolvedExercise.generatorId);
    final topic = topicForGenerator(resolvedExercise.generatorId);
    final db = ref.read(appDatabaseProvider);
    final settings = await db.settingsDao.getSettings();
    final newCardsPerDay = settings?.newCardsPerDay ?? 5;

    List<ExerciseQuestion> questions;

    if (topic != null) {
      List<String> allIds;
      if (selectedGroups != null) {
        final groups = generator.itemGroups(resolvedExercise);
        allIds = groups.entries
            .where((e) => selectedGroups.contains(e.key))
            .expand((e) => e.value)
            .toList();
      } else {
        allIds = generator.allItemIds(resolvedExercise);
      }
      final allIdSet = allIds.toSet();
      final now = DateTime.now();

      final scheduledIds =
          await db.itemSchedulesDao.getScheduledItemIds(topic);

      List<String> targetIds;

      if (learnedOnly) {
        // Practice all previously scheduled items (regardless of due date)
        targetIds = allIds.where((id) => scheduledIds.contains(id)).toList()
          ..shuffle();
      } else {
        // Due items to review
        final dueIds = await db.itemSchedulesDao.getDueItemIds(topic, now);
        final reviewIds =
            dueIds.where((id) => allIdSet.contains(id)).toList();

        // New items (not yet scheduled)
        final newIds =
            allIds.where((id) => !scheduledIds.contains(id)).toList();

        // Cap new items by global daily limit (unless overridden)
        int newSlots;
        if (ignoreNewCardLimit) {
          newSlots = newIds.length;
        } else if (newCardCount != null) {
          newSlots = newCardCount.clamp(0, newIds.length);
        } else {
          final newIntroducedToday =
              await db.itemSchedulesDao.getNewItemsIntroducedTodayGlobal();
          newSlots = (newCardsPerDay - newIntroducedToday).clamp(0, newIds.length);
        }
        final selectedNewIds = (newIds..shuffle()).take(newSlots).toList();

        targetIds = [...reviewIds, ...selectedNewIds];
      }

      if (targetIds.isEmpty) {
        // Nothing to do — set empty complete state
        state = const DrillSessionState(phase: DrillPhase.complete);
        return 0;
      }

      questions = generator.generateForItems(resolvedExercise, targetIds);
      questions.shuffle();
    } else {
      // Fallback for exercises without SRS topic tracking
      questions = generator.generate(resolvedExercise, count: 10);
    }

    final attemptId = const Uuid().v4();
    await db.exercisesDao.insertAttempt(ExerciseAttemptsCompanion.insert(
      id: attemptId,
      exerciseId: exercise.id,
      score: 0.0,
      durationSeconds: 0,
      timestamp: DateTime.now(),
      details: {},
    ));

    state = DrillSessionState(
      phase: DrillPhase.prompt,
      totalQuestions: questions.length,
      timeLimitSeconds: 0,
      currentQuestionIndex: 0,
      correctCount: 0,
      startTime: DateTime.now(),
      questions: questions,
      attemptId: attemptId,
      exerciseId: exercise.id,
    );

    return questions.length;
  }

  /// Starts a timed drill session targeting only "hard" items: those with
  /// 2+ lapses or low stability. Returns the number of questions (0 = no hard items).
  Future<int> startHardDrillSession({
    required Exercise exercise,
    Set<String>? selectedGroups,
    int timeLimitSeconds = 120,
  }) async {
    final resolvedExercise = await _resolveConfig(exercise);
    final generator = resolveGenerator(resolvedExercise.generatorId);
    final topic = topicForGenerator(resolvedExercise.generatorId);
    final db = ref.read(appDatabaseProvider);

    if (topic == null) {
      state = const DrillSessionState(phase: DrillPhase.complete);
      return 0;
    }

    // Get hard item IDs from SRS data
    final hardIds = await db.itemSchedulesDao.getHardItemIds(topic);

    // Filter to selected groups if specified
    List<String> targetIds;
    if (selectedGroups != null && selectedGroups.isNotEmpty) {
      final groups = generator.itemGroups(resolvedExercise);
      final groupItemIds = groups.entries
          .where((e) => selectedGroups.contains(e.key))
          .expand((e) => e.value)
          .toSet();
      targetIds = hardIds.where((id) => groupItemIds.contains(id)).toList();
    } else {
      final allIds = generator.allItemIds(resolvedExercise).toSet();
      targetIds = hardIds.where((id) => allIds.contains(id)).toList();
    }

    if (targetIds.isEmpty) {
      state = const DrillSessionState(phase: DrillPhase.complete);
      return 0;
    }

    final questions = generator.generateForItems(resolvedExercise, targetIds)
      ..shuffle();

    final attemptId = const Uuid().v4();
    await db.exercisesDao.insertAttempt(ExerciseAttemptsCompanion.insert(
      id: attemptId,
      exerciseId: exercise.id,
      score: 0.0,
      durationSeconds: 0,
      timestamp: DateTime.now(),
      details: {},
    ));

    state = DrillSessionState(
      phase: DrillPhase.prompt,
      totalQuestions: questions.length,
      timeLimitSeconds: timeLimitSeconds,
      currentQuestionIndex: 0,
      correctCount: 0,
      startTime: DateTime.now(),
      questions: questions,
      attemptId: attemptId,
      exerciseId: exercise.id,
    );

    return questions.length;
  }

  Future<Exercise> _resolveConfig(Exercise exercise) async {
    final config = Map<String, dynamic>.from(exercise.config);
    bool changed = false;

    // Apply note display style from settings
    final db = ref.read(appDatabaseProvider);
    final settings = await db.settingsDao.getSettings();
    final noteStyle = settings?.noteDisplayStyle ?? 'auto';
    if (noteStyle != 'auto') {
      config['noteDisplayStyle'] = noteStyle;
      changed = true;
    }

    // Merge unlocked progression config for this exercise's topic.
    // This ensures exercises only generate questions for items the user
    // has unlocked via the progression system.
    final topic = topicForGenerator(exercise.generatorId);
    if (topic != null) {
      final resolver = ref.read(progressionConfigResolverProvider);
      final unlocked = await resolver.getUnlockedConfig(topic);
      for (final key in ['intervals', 'roots', 'qualities']) {
        if (unlocked.containsKey(key) && !config.containsKey(key)) {
          config[key] = unlocked[key];
          changed = true;
        }
      }
    }

    if (!changed) return exercise;
    return exercise.copyWith(config: config);
  }

  void showInput() {
    state = state.copyWith(phase: DrillPhase.input);
  }

  bool _isSubmitting = false;

  Future<void> submitAnswer({required bool correct, int? rating, int responseTimeMs = 0}) async {
    if (_isSubmitting) return;
    _isSubmitting = true;
    try {
      await _submitAnswerInner(correct: correct, rating: rating, responseTimeMs: responseTimeMs);
    } finally {
      _isSubmitting = false;
    }
  }

  Future<void> _submitAnswerInner({required bool correct, int? rating, int responseTimeMs = 0}) async {
    final newCorrect = state.correctCount + (correct ? 1 : 0);
    final question = state.currentQuestion;
    final answeredIndex = state.currentQuestionIndex;

    DateTime? itemDue;

    // Record question result, progression attempt, and SRS schedule
    if (question != null) {
      await _recordQuestionResult(
        question: question,
        questionIndex: answeredIndex,
        correct: correct,
        responseTimeMs: responseTimeMs,
      );
      await _recordProgressionAttempt(question, correct);
      itemDue = await _recordItemSchedule(question, correct, rating);
    }

    final isLastQuestion = answeredIndex + 1 >= state.totalQuestions;

    if (isLastQuestion) {
      await _finalizeAttempt(newCorrect, answeredIndex + 1);
      state = state.copyWith(
        phase: DrillPhase.complete,
        correctCount: newCorrect,
        lastAnswerCorrect: correct,
        lastItemDue: itemDue,
      );
    } else {
      state = state.copyWith(
        phase: DrillPhase.feedback,
        correctCount: newCorrect,
        lastAnswerCorrect: correct,
        lastItemDue: itemDue,
      );
    }
  }

  void nextQuestion() {
    if (state.phase == DrillPhase.complete) return;
    state = state.copyWith(
      phase: DrillPhase.prompt,
      currentQuestionIndex: state.currentQuestionIndex + 1,
      lastAnswerCorrect: null,
      lastItemDue: null,
    );
  }

  /// Re-queues the current question at the end of the session.
  void repeatCurrentQuestion() {
    final current = state.currentQuestion;
    if (current == null) return;
    state = state.copyWith(
      questions: [...state.questions, current],
      totalQuestions: state.totalQuestions + 1,
    );
  }

  Future<void> _recordQuestionResult({
    required ExerciseQuestion question,
    required int questionIndex,
    required bool correct,
    required int responseTimeMs,
  }) async {
    if (state.attemptId == null) return;
    final db = ref.read(appDatabaseProvider);
    final meta = question.metadata;

    await db.questionResultsDao.insertResult(QuestionResultsCompanion.insert(
      attemptId: state.attemptId!,
      questionIndex: questionIndex,
      correct: correct,
      responseTimeMs: responseTimeMs,
      topic: (meta['topic'] as String?) ?? '',
      skill: (meta['skill'] as String?) ?? '',
      itemId: (meta['itemId'] as String?) ?? '',
      keyRoot: Value(meta['root'] as int?),
      metadata: Value(meta),
    ));
  }

  Future<void> _recordProgressionAttempt(
    ExerciseQuestion question,
    bool correct,
  ) async {
    final meta = question.metadata;
    final topic = meta['topic'] as String?;
    if (topic == null) return;

    final resolver = ref.read(progressionConfigResolverProvider);
    final semitones = meta['interval'] as int?;
    final itemId = (meta['itemId'] as String?) ?? '';

    final tierId =
        await resolver.findTierForItem(topic, itemId, semitones);
    if (tierId == null) return;

    final progressionService = ref.read(progressionServiceProvider);
    await progressionService.recordAttempt(tierId, correct: correct);
  }

  Future<DateTime?> _recordItemSchedule(
    ExerciseQuestion question,
    bool correct,
    int? ratingOverride,
  ) async {
    final meta = question.metadata;
    final topic = meta['topic'] as String?;
    final itemId = meta['itemId'] as String?;
    if (topic == null || itemId == null) return null;

    final db = ref.read(appDatabaseProvider);
    final adapter = ref.read(fsrsAdapterProvider);

    return db.transaction(() async {
      // Load existing schedule or create a new one
      final existing = await db.itemSchedulesDao.getSchedule(topic, itemId);
      final now = DateTime.now().toUtc();
      final currentState = existing != null
          ? SrsCardState(
              cardId: '$topic:$itemId',
              due: existing.due,
              stability: existing.stability,
              difficulty: existing.difficulty,
              interval: existing.interval,
              lapses: existing.lapses,
              reps: existing.reps,
              state: existing.state,
              lastReview: existing.lastReview,
              step: existing.step,
            )
          : SrsCardState(cardId: '$topic:$itemId', due: now);

      final rating = ratingOverride ?? (correct ? 2 : 0);
      final newState = adapter.review(currentState, rating, now: now);

      await db.itemSchedulesDao.upsertSchedule(ItemSchedulesCompanion.insert(
        topic: topic,
        itemId: itemId,
        due: newState.due,
        stability: Value(newState.stability),
        difficulty: Value(newState.difficulty),
        interval: Value(newState.interval),
        lapses: Value(newState.lapses),
        reps: Value(newState.reps),
        state: Value(newState.state),
        lastReview: Value(newState.lastReview),
        step: Value(newState.step),
      ));

      return newState.due;
    });
  }

  Future<void> _finalizeAttempt(int correctCount, int totalAnswered) async {
    if (state.attemptId == null) return;
    final db = ref.read(appDatabaseProvider);
    final duration = state.startTime != null
        ? DateTime.now().difference(state.startTime!).inSeconds
        : 0;
    final score =
        totalAnswered > 0 ? correctCount / totalAnswered : 0.0;

    await (db.update(db.exerciseAttempts)
          ..where((a) => a.id.equals(state.attemptId!)))
        .write(ExerciseAttemptsCompanion(
      score: Value(score),
      durationSeconds: Value(duration),
      details: Value({
        'totalQuestions': state.totalQuestions,
        'correctCount': correctCount,
        'totalAnswered': totalAnswered,
      }),
    ));
  }
}

class DrillSessionState {
  final DrillPhase phase;
  final int totalQuestions;
  final int timeLimitSeconds;
  final int currentQuestionIndex;
  final int correctCount;
  final bool? lastAnswerCorrect;
  final DateTime? lastItemDue;
  final DateTime? startTime;
  final List<ExerciseQuestion> questions;
  final String? attemptId;
  final String? exerciseId;

  const DrillSessionState({
    this.phase = DrillPhase.prompt,
    this.totalQuestions = 10,
    this.timeLimitSeconds = 120,
    this.currentQuestionIndex = 0,
    this.correctCount = 0,
    this.lastAnswerCorrect,
    this.lastItemDue,
    this.startTime,
    this.questions = const [],
    this.attemptId,
    this.exerciseId,
  });

  ExerciseQuestion? get currentQuestion {
    if (questions.isEmpty || currentQuestionIndex >= questions.length) {
      return null;
    }
    return questions[currentQuestionIndex];
  }

  static const _sentinel = Object();

  DrillSessionState copyWith({
    DrillPhase? phase,
    int? totalQuestions,
    int? timeLimitSeconds,
    int? currentQuestionIndex,
    int? correctCount,
    Object? lastAnswerCorrect = _sentinel,
    Object? lastItemDue = _sentinel,
    DateTime? startTime,
    List<ExerciseQuestion>? questions,
    String? attemptId,
    String? exerciseId,
  }) {
    return DrillSessionState(
      phase: phase ?? this.phase,
      totalQuestions: totalQuestions ?? this.totalQuestions,
      timeLimitSeconds: timeLimitSeconds ?? this.timeLimitSeconds,
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      correctCount: correctCount ?? this.correctCount,
      lastAnswerCorrect: lastAnswerCorrect == _sentinel
          ? this.lastAnswerCorrect
          : lastAnswerCorrect as bool?,
      lastItemDue: lastItemDue == _sentinel
          ? this.lastItemDue
          : lastItemDue as DateTime?,
      startTime: startTime ?? this.startTime,
      questions: questions ?? this.questions,
      attemptId: attemptId ?? this.attemptId,
      exerciseId: exerciseId ?? this.exerciseId,
    );
  }

  int get answeredCount {
    if (phase == DrillPhase.complete) return totalQuestions;
    // During feedback, the current question has been answered but
    // currentQuestionIndex hasn't advanced yet, so add 1.
    if (phase == DrillPhase.feedback) return currentQuestionIndex + 1;
    return currentQuestionIndex;
  }

  double get progress =>
      totalQuestions > 0 ? answeredCount / totalQuestions : 0.0;

  int get score =>
      answeredCount > 0
          ? ((correctCount / answeredCount) * 100).round()
          : 0;
}
