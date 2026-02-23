import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/providers.dart';
import '../../../core/constants/refresh_intervals.dart';
import '../../../core/constants/srs_defaults.dart';

part 'streak_provider.g.dart';

enum StreakActivitySource { theory, practice, both }

class StreakDayStatus {
  final DateTime dayLocal;
  final bool isActive;
  final bool isToday;

  const StreakDayStatus({
    required this.dayLocal,
    required this.isActive,
    required this.isToday,
  });
}

class TodayStreakState {
  final int currentStreakDays;
  final int bestStreakDays;
  final bool todayComplete;
  final bool canContinueToday;
  final DateTime? lastActiveStudyDayLocal;
  final StreakActivitySource source;
  final List<StreakDayStatus> lastSevenDays;
  final double todayProgress;

  const TodayStreakState({
    this.currentStreakDays = 0,
    this.bestStreakDays = 0,
    this.todayComplete = false,
    this.canContinueToday = false,
    this.lastActiveStudyDayLocal,
    this.source = StreakActivitySource.both,
    this.lastSevenDays = const [],
    this.todayProgress = 0,
  });
}

StreakActivitySource _parseSource(String? raw) {
  return switch (raw) {
    'theory' => StreakActivitySource.theory,
    'practice' => StreakActivitySource.practice,
    _ => StreakActivitySource.both,
  };
}

DateTime _studyDayDateLocal(DateTime timestamp, int rolloverHourLocal) {
  final shifted = timestamp.toLocal().subtract(Duration(hours: rolloverHourLocal));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

double _currentStudyDayProgress(int rolloverHourLocal) {
  final now = DateTime.now();
  var start = DateTime(now.year, now.month, now.day, rolloverHourLocal);
  if (now.isBefore(start)) {
    start = start.subtract(const Duration(days: 1));
  }
  final end = start.add(const Duration(days: 1));
  final totalMs = end.difference(start).inMilliseconds;
  if (totalMs <= 0) return 0;
  final elapsedMs = now.difference(start).inMilliseconds;
  return (elapsedMs / totalMs).clamp(0, 1).toDouble();
}

TodayStreakState _computeStreak({
  required List<DateTime> timestamps,
  required int rolloverHourLocal,
  required StreakActivitySource source,
}) {
  final days = timestamps
      .map((ts) => _studyDayDateLocal(ts, rolloverHourLocal))
      .toSet()
      .toList()
    ..sort();

  if (days.isEmpty) {
    return TodayStreakState(source: source);
  }

  final today = _studyDayDateLocal(DateTime.now(), rolloverHourLocal);
  final activeSet = days.map((d) => d.millisecondsSinceEpoch).toSet();
  final todayComplete = activeSet.contains(today.millisecondsSinceEpoch);
  final todayProgress = _currentStudyDayProgress(rolloverHourLocal);

  var best = 1;
  var run = 1;
  for (var i = 1; i < days.length; i++) {
    if (days[i].difference(days[i - 1]).inDays == 1) {
      run++;
      if (run > best) best = run;
    } else {
      run = 1;
    }
  }

  var probe = todayComplete ? today : today.subtract(const Duration(days: 1));
  var current = 0;
  while (activeSet.contains(probe.millisecondsSinceEpoch)) {
    current++;
    probe = probe.subtract(const Duration(days: 1));
  }

  final yesterday = today.subtract(const Duration(days: 1));
  final canContinueToday = !todayComplete &&
      activeSet.contains(yesterday.millisecondsSinceEpoch) &&
      current > 0;

  final lastSeven = List<StreakDayStatus>.generate(7, (i) {
    final day = today.subtract(Duration(days: 6 - i));
    return StreakDayStatus(
      dayLocal: day,
      isActive: activeSet.contains(day.millisecondsSinceEpoch),
      isToday: i == 6,
    );
  });

  return TodayStreakState(
    currentStreakDays: current,
    bestStreakDays: best,
    todayComplete: todayComplete,
    canContinueToday: canContinueToday,
    lastActiveStudyDayLocal: days.last,
    source: source,
    lastSevenDays: lastSeven,
    todayProgress: todayProgress,
  );
}

@riverpod
Stream<TodayStreakState> todayStreak(TodayStreakRef ref) async* {
  final db = ref.watch(appDatabaseProvider);
  while (true) {
    final settings = await db.settingsDao.getSettings();
    final source = _parseSource(settings?.streakActivitySource);
    final rolloverHour = settings?.dayRolloverHour ?? kDefaultDayRolloverHour;

    final timestamps = <DateTime>[];
    if (source == StreakActivitySource.theory ||
        source == StreakActivitySource.both) {
      timestamps.addAll(await db.reviewsDao.getAllReviewTimestamps());
    }
    if (source == StreakActivitySource.practice ||
        source == StreakActivitySource.both) {
      timestamps.addAll(await db.questionResultsDao.getAnsweredAttemptTimestamps());
    }

    yield _computeStreak(
      timestamps: timestamps,
      rolloverHourLocal: rolloverHour,
      source: source,
    );

    await Future<void>.delayed(kFastCountRefreshInterval);
  }
}
