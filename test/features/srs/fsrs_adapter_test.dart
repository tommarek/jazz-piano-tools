import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/domain/models/srs_card_state.dart';
import 'package:jazz_piano_tools/features/srs/fsrs_adapter.dart';

void main() {
  late FsrsAdapter adapter;

  setUp(() {
    adapter = FsrsAdapter();
  });

  group('FsrsAdapter', () {
    test('new card reviewed with good moves due forward', () {
      final state = SrsCardState(
        cardId: 'card1',
        due: DateTime.now().toUtc(),
        state: 'new',
      );
      final result = adapter.review(state, 2); // good
      expect(result.due.isAfter(DateTime.now()), isTrue);
      expect(result.stability, greaterThan(0));
    });

    test('new card reviewed with again stays due soon', () {
      final state = SrsCardState(
        cardId: 'card1',
        due: DateTime.now().toUtc(),
        state: 'new',
      );
      final result = adapter.review(state, 0); // again
      // Should be due within minutes/hours, not days
      final diff = result.due.difference(DateTime.now().toUtc());
      expect(diff.inDays, lessThan(1));
    });

    test('new card reviewed with easy moves due further than good', () {
      final state = SrsCardState(
        cardId: 'card1',
        due: DateTime.now().toUtc(),
        state: 'new',
      );
      final goodResult = adapter.review(state, 2); // good
      final easyResult = adapter.review(state, 3); // easy
      expect(
        easyResult.due.isAfter(goodResult.due) ||
            easyResult.due.isAtSameMomentAs(goodResult.due),
        isTrue,
      );
    });

    test('review updates state field', () {
      final state = SrsCardState(
        cardId: 'card1',
        due: DateTime.now().toUtc(),
        state: 'new',
      );
      final result = adapter.review(state, 2); // good
      expect(result.state, isNot('new'));
    });

    test('getRetrievability returns value between 0 and 1', () {
      final state = SrsCardState(
        cardId: 'card1',
        due: DateTime.now().toUtc(),
        stability: 5.0,
        difficulty: 3.0,
        reps: 1,
        state: 'review',
      );
      final r = adapter.getRetrievability(state);
      expect(r, greaterThanOrEqualTo(0));
      expect(r, lessThanOrEqualTo(1));
    });
  });
}
