import '../../../domain/models/exercise.dart';
import 'exercise_question.dart';

abstract class QuestionGenerator {
  List<ExerciseQuestion> generate(Exercise exercise, {int count = 10});
}
