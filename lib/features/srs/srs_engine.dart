import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../database/app_database.dart';
import '../../domain/enums/answer_type.dart';
import '../../domain/models/srs_card.dart' as domain;
import '../../domain/models/srs_card_state.dart' as domain;
import 'fsrs_adapter.dart';

class SrsQueueStats {
  final int learningDue;
  final int reviewDue;
  final int newAvailableToday;

  const SrsQueueStats({
    this.learningDue = 0,
    this.reviewDue = 0,
    this.newAvailableToday = 0,
  });

  int get totalDue => learningDue + reviewDue;
}

class SrsEngine {
  final AppDatabase _db;
  final FsrsAdapter _adapter;
  /// Optional callback invoked after a review is recorded, so providers
  /// watching due-card state can be invalidated.
  void Function()? onReviewRecorded;
  static const _uuid = Uuid();

  SrsEngine(this._db, this._adapter);

  DateTime _studyDayStartUtc(int rolloverHourLocal) {
    final nowLocal = DateTime.now();
    var startLocal = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
      rolloverHourLocal,
    );
    if (nowLocal.isBefore(startLocal)) {
      startLocal = startLocal.subtract(const Duration(days: 1));
    }
    return startLocal.toUtc();
  }

  DateTime _nextStudyDayBoundaryUtc(int rolloverHourLocal) {
    return _studyDayStartUtc(rolloverHourLocal).add(const Duration(days: 1));
  }

  DateTime _scheduleLearningDue(
    DateTime nowUtc,
    int delayMinutes,
    int rolloverHourLocal,
  ) {
    if (delayMinutes <= 0) return nowUtc;
    final directDue = nowUtc.add(Duration(minutes: delayMinutes));
    final nextBoundary = _nextStudyDayBoundaryUtc(rolloverHourLocal);
    // Anki-style: if a learning step crosses the day boundary, schedule by days.
    if (directDue.isAfter(nextBoundary)) {
      final days = (delayMinutes / (24 * 60)).ceil().clamp(1, 36500);
      return nextBoundary.add(Duration(days: days - 1));
    }
    return directDue;
  }

  List<int> _parseSteps(String raw, List<int> fallback) {
    final parsed = raw
        .split(',')
        .map((s) => int.tryParse(s.trim()) ?? -1)
        .where((n) => n > 0)
        .toList();
    return parsed.isEmpty ? fallback : parsed;
  }

  Future<int> _newCardsRemainingTodayForSettings(Setting? settings) async {
    final newCardsPerDay = settings?.newCardsPerDay ?? 5;
    final rolloverHour = settings?.dayRolloverHour ?? 4;
    final dayStart = _studyDayStartUtc(rolloverHour);
    final introducedToday =
        await _db.reviewsDao.getCardsFirstReviewedSince(dayStart);
    final remaining = newCardsPerDay - introducedToday;
    return remaining > 0 ? remaining : 0;
  }

  Future<int> _reviewCardsRemainingTodayForSettings(Setting? settings) async {
    final reviewCardsPerDay = settings?.reviewCardsPerDay ?? 200;
    final rolloverHour = settings?.dayRolloverHour ?? 4;
    final dayStart = _studyDayStartUtc(rolloverHour);
    final reviewsDoneToday = (await _db.reviewsDao.getReviewsSince(dayStart)).length;
    final remaining = reviewCardsPerDay - reviewsDoneToday;
    return remaining > 0 ? remaining : 0;
  }

  Future<SrsQueueStats> getQueueStats() async {
    final settings = await _db.settingsDao.getSettings();
    final now = DateTime.now().toUtc();
    final learningDue =
        await _db.cardsDao.getDueLearningCardIds(now, learnAhead: Duration.zero);
    final reviewDue = await _db.cardsDao.getDueReviewCardIds(now);
    final reviewRemaining = await _reviewCardsRemainingTodayForSettings(settings);
    final newRemaining = await _newCardsRemainingTodayForSettings(settings);

    return SrsQueueStats(
      // Dashboard should show only truly due cards, not learn-ahead cards.
      learningDue: learningDue.length,
      reviewDue: reviewDue.length.clamp(0, reviewRemaining),
      newAvailableToday: newRemaining,
    );
  }

  Future<List<String>> getStudyQueueCardIds() async {
    final settings = await _db.settingsDao.getSettings();
    final now = DateTime.now().toUtc();
    final learnAhead = Duration(minutes: settings?.learnAheadMinutes ?? 20);

    final learningDue =
        await _db.cardsDao.getDueLearningCardIds(now, learnAhead: Duration.zero);
    final reviewDue = await _db.cardsDao.getDueReviewCardIds(now);
    final reviewRemaining = await _reviewCardsRemainingTodayForSettings(settings);
    final newRemaining = await _newCardsRemainingTodayForSettings(settings);

    final effectiveLearning = <String>[...learningDue];
    // Anki learn-ahead: only pull ahead learning cards when no cards are due.
    if (effectiveLearning.isEmpty && reviewDue.isEmpty && learnAhead > Duration.zero) {
      final upcoming = await _db.cardsDao.getDueLearningCardIds(
        now,
        learnAhead: learnAhead,
      );
      effectiveLearning.addAll(upcoming);
    }

    final reviewQueue = reviewDue.take(reviewRemaining).toList();
    final newQueue = await _db.cardsDao.getNewCardIds(limit: newRemaining);

    return <String>[
      ...effectiveLearning,
      ...reviewQueue,
      ...newQueue,
    ];
  }

  Future<List<String>> getDueCardIds() async {
    final now = DateTime.now().toUtc();
    final learningDue = await _db.cardsDao.getDueLearningCardIds(now);
    final reviewDue = await _db.cardsDao.getDueReviewCardIds(now);
    return [...learningDue, ...reviewDue];
  }

  Future<int> getNewCardsRemainingToday() async {
    final settings = await _db.settingsDao.getSettings();
    return _newCardsRemainingTodayForSettings(settings);
  }

  Future<(domain.SrsCard, domain.SrsCardState)> getCardForReview(
    String cardId,
  ) async {
    final card = await _db.cardsDao.getCardById(cardId);
    if (card == null) {
      throw StateError('Card not found: $cardId');
    }
    final state = await _db.cardsDao.getCardState(cardId);

    final domainCard = domain.SrsCard(
      id: card.id,
      deckId: card.deckId,
      prompt: card.prompt,
      expectedAnswer: card.expectedAnswer,
      answerType: AnswerType.values.byName(card.answerType),
      metadata: card.metadata,
    );

    final domainState = state != null
        ? domain.SrsCardState(
            cardId: state.cardId,
            due: state.due,
            stability: state.stability,
            difficulty: state.difficulty,
            interval: state.interval,
            lapses: state.lapses,
            reps: state.reps,
            state: state.state,
            lastReview: state.lastReview,
            step: state.step,
          )
        : domain.SrsCardState(
            cardId: cardId,
            due: DateTime.now().toUtc(),
          );

    return (domainCard, domainState);
  }

  Future<domain.SrsCardState> recordReview(
    String cardId,
    int rating,
    int responseTimeMs,
  ) async {
    final now = DateTime.now().toUtc();
    final settings = await _db.settingsDao.getSettings();
    final (_, currentState) = await getCardForReview(cardId);
    late final domain.SrsCardState newState;

    final learningSteps = _parseSteps(
      settings?.learningStepsMinutes ?? '1,10',
      const [1, 10],
    );
    final relearningSteps = _parseSteps(
      settings?.relearningStepsMinutes ?? '10',
      const [10],
    );
    final rolloverHour = settings?.dayRolloverHour ?? 4;
    final graduatingIntervalDays = settings?.graduatingIntervalDays ?? 1;
    final easyIntervalDays = settings?.easyIntervalDays ?? 4;

    if (currentState.state == 'new' ||
        currentState.state == 'learning' ||
        currentState.state == 'relearning') {
      final inRelearning = currentState.state == 'relearning';
      final steps = inRelearning ? relearningSteps : learningSteps;
      final currentStep = currentState.step ?? 0;

      if (rating == 0) {
        // Again: restart current learning/relearning queue.
        newState = currentState.copyWith(
          due: _scheduleLearningDue(now, steps.first, rolloverHour),
          state: inRelearning ? 'relearning' : 'learning',
          step: 0,
          reps: currentState.reps + 1,
          lastReview: now,
        );
      } else if (rating == 1) {
        // Hard:
        // - first step: average first two steps (or 1.5x when only one step)
        // - later steps: stay on current step
        final stepIndex = currentStep.clamp(0, steps.length - 1);
        final hardDelay = stepIndex == 0
            ? (steps.length >= 2
                ? ((steps[0] + steps[1]) / 2).round()
                : (steps[0] * 1.5).round())
            : steps[stepIndex];
        newState = currentState.copyWith(
          due: _scheduleLearningDue(now, hardDelay, rolloverHour),
          state: inRelearning ? 'relearning' : 'learning',
          step: stepIndex,
          reps: currentState.reps + 1,
          lastReview: now,
        );
      } else {
        if (rating >= 3) {
          // Easy graduates immediately. Run through FSRS once to initialize
          // review parameters, then enforce the fixed easy interval.
          final seeded = _adapter.review(currentState, rating, now: now);
          newState = seeded.copyWith(
            due: _nextStudyDayBoundaryUtc(rolloverHour).add(
              Duration(days: (easyIntervalDays - 1).clamp(0, 36500)),
            ),
            state: 'review',
            step: null,
            lastReview: now,
          );
        } else {
        final nextStep = currentStep + 1;
        if (nextStep < steps.length) {
          // Continue through learning steps.
          newState = currentState.copyWith(
            due: _scheduleLearningDue(now, steps[nextStep], rolloverHour),
            state: inRelearning ? 'relearning' : 'learning',
            step: nextStep,
            reps: currentState.reps + 1,
            lastReview: now,
          );
        } else {
          // Good at last step graduates with configured interval.
          // Seed FSRS parameters to avoid null-state crashes on next review.
          final seeded = _adapter.review(currentState, rating, now: now);
          newState = seeded.copyWith(
            due: _nextStudyDayBoundaryUtc(rolloverHour).add(
              Duration(days: (graduatingIntervalDays - 1).clamp(0, 36500)),
            ),
            state: 'review',
            step: null,
            lastReview: now,
          );
        }
        }
      }
    } else {
      if (rating == 0 && relearningSteps.isNotEmpty) {
        // Lapse: move to relearning steps.
        newState = currentState.copyWith(
          due: _scheduleLearningDue(now, relearningSteps.first, rolloverHour),
          state: 'relearning',
          step: 0,
          lapses: currentState.lapses + 1,
          reps: currentState.reps + 1,
          lastReview: now,
        );
      } else {
        newState = _adapter.review(currentState, rating, now: now);
      }
    }

    await _db.transaction(() async {
      await _db.cardsDao.upsertCardState(CardStatesCompanion.insert(
        cardId: cardId,
        due: newState.due,
        stability: newState.stability,
        difficulty: newState.difficulty,
        interval: newState.interval,
        lapses: newState.lapses,
        reps: newState.reps,
        state: newState.state,
        lastReview: Value(newState.lastReview),
        step: Value(newState.step),
      ));

      await _db.reviewsDao.insertReview(ReviewsCompanion.insert(
        id: _uuid.v4(),
        cardId: cardId,
        timestamp: now,
        rating: rating,
        responseTimeMs: responseTimeMs,
      ));
    });

    onReviewRecorded?.call();
    return newState;
  }
}
