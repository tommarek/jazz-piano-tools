import 'package:freezed_annotation/freezed_annotation.dart';

part 'srs_card_state.freezed.dart';
part 'srs_card_state.g.dart';

@freezed
abstract class SrsCardState with _$SrsCardState {
  const factory SrsCardState({
    required String cardId,
    required DateTime due,
    @Default(0.0) double stability,
    @Default(0.0) double difficulty,
    @Default(0) int interval,
    @Default(0) int lapses,
    @Default(0) int reps,
    @Default('new') String state,
  }) = _SrsCardState;

  factory SrsCardState.fromJson(Map<String, dynamic> json) =>
      _$SrsCardStateFromJson(json);
}
