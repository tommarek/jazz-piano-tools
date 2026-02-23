import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/cards_table.dart';
import '../tables/reviews_table.dart';

part 'reviews_dao.g.dart';

@DriftAccessor(tables: [Reviews, Cards])
class ReviewsDao extends DatabaseAccessor<AppDatabase> with _$ReviewsDaoMixin {
  ReviewsDao(super.db);

  Future<void> insertReview(ReviewsCompanion companion) {
    return into(reviews).insert(companion);
  }

  Future<List<Review>> getReviewsForCard(String cardId) {
    return (select(reviews)..where((r) => r.cardId.equals(cardId))).get();
  }

  Future<List<Review>> getReviewsSince(DateTime since) {
    return (select(reviews)..where((r) => r.timestamp.isBiggerOrEqualValue(since)))
        .get();
  }

  Future<List<DateTime>> getAllReviewTimestamps() async {
    final rows = await (selectOnly(reviews)..addColumns([reviews.timestamp])).get();
    return rows.map((r) => r.read(reviews.timestamp)!).toList();
  }

  Future<int> getReviewCount() async {
    final count = countAll();
    final query = selectOnly(reviews)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// Counts cards whose first-ever review happened at or after [since].
  Future<int> getCardsFirstReviewedSince(
    DateTime since, {
    List<String>? deckIds,
  }) async {
    if (deckIds == null || deckIds.isEmpty) {
      final row = await customSelect(
        '''
        SELECT COUNT(*) AS c
        FROM (
          SELECT card_id
          FROM reviews
          GROUP BY card_id
          HAVING MIN(timestamp) >= ?1
        ) t
        ''',
        variables: [Variable<DateTime>(since)],
        readsFrom: {reviews},
      ).getSingle();
      return row.read<int>('c');
    }

    final placeholders = List.generate(deckIds.length, (i) => '?${i + 2}').join(',');
    final variables = <Variable>[
      Variable<DateTime>(since),
      ...deckIds.map((id) => Variable<String>(id)),
    ];

    final row = await customSelect(
      '''
      SELECT COUNT(*) AS c
      FROM (
        SELECT r.card_id
        FROM reviews r
        INNER JOIN cards c ON c.id = r.card_id
        WHERE c.deck_id IN ($placeholders)
        GROUP BY r.card_id
        HAVING MIN(r.timestamp) >= ?1
      ) t
      ''',
      variables: variables,
      readsFrom: {reviews, cards},
    ).getSingle();
    return row.read<int>('c');
  }

  /// Counts cards whose first-ever review happened today (UTC day boundary).
  Future<int> getCardsFirstReviewedToday({List<String>? deckIds}) {
    final now = DateTime.now().toUtc();
    final todayStart = DateTime.utc(now.year, now.month, now.day);
    return getCardsFirstReviewedSince(todayStart, deckIds: deckIds);
  }
}
