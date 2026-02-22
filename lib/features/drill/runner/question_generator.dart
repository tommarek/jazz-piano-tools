import '../../../domain/models/exercise.dart';
import 'exercise_question.dart';

abstract class QuestionGenerator {
  List<ExerciseQuestion> generate(Exercise exercise, {int count = 10});

  /// Returns all unique item IDs this generator can produce for [exercise].
  List<String> allItemIds(Exercise exercise);

  /// Generates one question for each specified [itemIds].
  List<ExerciseQuestion> generateForItems(
      Exercise exercise, List<String> itemIds);

  /// Returns groups of item IDs: group name -> list of item IDs in that group.
  /// Used for UI grouping and selective practice.
  Map<String, List<String>> itemGroups(Exercise exercise) {
    return {'All': allItemIds(exercise)};
  }
}
