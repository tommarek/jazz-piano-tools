import 'package:freezed_annotation/freezed_annotation.dart';

import '../enums/answer_type.dart';

part 'srs_card.freezed.dart';
part 'srs_card.g.dart';

@freezed
abstract class SrsCard with _$SrsCard {
  const factory SrsCard({
    required String id,
    required String deckId,
    required String prompt,
    required String expectedAnswer,
    required AnswerType answerType,
    @Default({}) Map<String, dynamic> metadata,
  }) = _SrsCard;

  factory SrsCard.fromJson(Map<String, dynamic> json) =>
      _$SrsCardFromJson(json);
}
