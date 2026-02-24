import 'package:freezed_annotation/freezed_annotation.dart';

part 'deck.freezed.dart';
part 'deck.g.dart';

@freezed
abstract class Deck with _$Deck {
  const factory Deck({
    required String id,
    required String title,
    @Default([]) List<String> tags,
    String? sourceConceptId,
    String? parentId,
    @Default(false) bool excludeFromDailyReview,
  }) = _Deck;

  factory Deck.fromJson(Map<String, dynamic> json) => _$DeckFromJson(json);
}
