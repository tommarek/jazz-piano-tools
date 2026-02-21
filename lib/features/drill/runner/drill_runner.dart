import 'exercise_runner.dart';

/// A timed drill runner that enforces an optional time limit.
class DrillRunner extends ExerciseRunner {
  final Duration? timeLimit;

  DrillRunner({
    required super.exercise,
    required super.generator,
    required super.checkAnswer,
    this.timeLimit,
  });

  /// Whether the time limit has been exceeded.
  bool get isTimeUp {
    if (timeLimit == null) return false;
    return elapsed >= timeLimit!;
  }

  /// Time remaining before the drill ends, or [Duration.zero] if no limit
  /// is set or time has already expired.
  Duration get remainingTime {
    if (timeLimit == null) return Duration.zero;
    final remaining = timeLimit! - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  bool get isComplete => super.isComplete || isTimeUp;
}
