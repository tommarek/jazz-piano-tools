import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../srs/providers/srs_provider.dart';

part 'today_session_provider.g.dart';

class TodaySessionState {
  final int dueCardCount;
  final int completedReviews;
  final List<String> suggestedDrillIds;
  final List<String> suggestedPracticeIds;
  final int sessionEstimateMinutes;

  const TodaySessionState({
    this.dueCardCount = 0,
    this.completedReviews = 0,
    this.suggestedDrillIds = const [],
    this.suggestedPracticeIds = const [],
    this.sessionEstimateMinutes = 0,
  });

  TodaySessionState copyWith({
    int? dueCardCount,
    int? completedReviews,
    List<String>? suggestedDrillIds,
    List<String>? suggestedPracticeIds,
    int? sessionEstimateMinutes,
  }) {
    return TodaySessionState(
      dueCardCount: dueCardCount ?? this.dueCardCount,
      completedReviews: completedReviews ?? this.completedReviews,
      suggestedDrillIds: suggestedDrillIds ?? this.suggestedDrillIds,
      suggestedPracticeIds: suggestedPracticeIds ?? this.suggestedPracticeIds,
      sessionEstimateMinutes:
          sessionEstimateMinutes ?? this.sessionEstimateMinutes,
    );
  }
}

@riverpod
Future<TodaySessionState> todaySession(TodaySessionRef ref) async {
  final dueCount = await ref.watch(dueCardCountProvider.future);

  // Estimate: ~30 seconds per card review, plus suggested drill/practice time
  final reviewMinutes = (dueCount * 0.5).ceil();
  final drillMinutes = 5;
  final practiceMinutes = 5;
  final totalEstimate = reviewMinutes + drillMinutes + practiceMinutes;

  return TodaySessionState(
    dueCardCount: dueCount,
    completedReviews: 0,
    suggestedDrillIds: const ['interval-drill', 'chord-quality-drill'],
    suggestedPracticeIds: const ['voicing-practice'],
    sessionEstimateMinutes: totalEstimate,
  );
}
