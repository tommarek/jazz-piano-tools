import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../content/providers/content_providers.dart';
import '../../../domain/models/exercise.dart';

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

  void startDrill({required int totalQuestions, required int timeLimitSeconds}) {
    state = DrillSessionState(
      phase: DrillPhase.prompt,
      totalQuestions: totalQuestions,
      timeLimitSeconds: timeLimitSeconds,
      currentQuestion: 0,
      correctCount: 0,
      startTime: DateTime.now(),
    );
  }

  void showInput() {
    state = state.copyWith(phase: DrillPhase.input);
  }

  void submitAnswer({required bool correct}) {
    final newCorrect = state.correctCount + (correct ? 1 : 0);
    final newQuestion = state.currentQuestion + 1;

    if (newQuestion >= state.totalQuestions) {
      state = state.copyWith(
        phase: DrillPhase.complete,
        currentQuestion: newQuestion,
        correctCount: newCorrect,
      );
    } else {
      state = state.copyWith(
        phase: DrillPhase.feedback,
        currentQuestion: newQuestion,
        correctCount: newCorrect,
        lastAnswerCorrect: correct,
      );
    }
  }

  void nextQuestion() {
    state = state.copyWith(phase: DrillPhase.prompt);
  }
}

class DrillSessionState {
  final DrillPhase phase;
  final int totalQuestions;
  final int timeLimitSeconds;
  final int currentQuestion;
  final int correctCount;
  final bool? lastAnswerCorrect;
  final DateTime? startTime;

  const DrillSessionState({
    this.phase = DrillPhase.prompt,
    this.totalQuestions = 10,
    this.timeLimitSeconds = 120,
    this.currentQuestion = 0,
    this.correctCount = 0,
    this.lastAnswerCorrect,
    this.startTime,
  });

  DrillSessionState copyWith({
    DrillPhase? phase,
    int? totalQuestions,
    int? timeLimitSeconds,
    int? currentQuestion,
    int? correctCount,
    bool? lastAnswerCorrect,
    DateTime? startTime,
  }) {
    return DrillSessionState(
      phase: phase ?? this.phase,
      totalQuestions: totalQuestions ?? this.totalQuestions,
      timeLimitSeconds: timeLimitSeconds ?? this.timeLimitSeconds,
      currentQuestion: currentQuestion ?? this.currentQuestion,
      correctCount: correctCount ?? this.correctCount,
      lastAnswerCorrect: lastAnswerCorrect ?? this.lastAnswerCorrect,
      startTime: startTime ?? this.startTime,
    );
  }

  double get progress =>
      totalQuestions > 0 ? currentQuestion / totalQuestions : 0.0;

  int get score =>
      currentQuestion > 0
          ? ((correctCount / currentQuestion) * 100).round()
          : 0;
}
