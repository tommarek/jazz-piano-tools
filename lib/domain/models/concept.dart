import 'package:freezed_annotation/freezed_annotation.dart';

part 'concept.freezed.dart';
part 'concept.g.dart';

@freezed
abstract class Concept with _$Concept {
  const factory Concept({
    required String id,
    required String title,
    required String summary,
    required String bodyMarkdown,
    @Default([]) List<Map<String, dynamic>> examples,
    @Default([]) List<String> tags,
    @Default(1) int level,
    @Default([]) List<String> relatedExerciseIds,
    @Default([]) List<String> relatedCardDeckIds,
  }) = _Concept;

  factory Concept.fromJson(Map<String, dynamic> json) =>
      _$ConceptFromJson(json);
}
