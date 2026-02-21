import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/reviews_table.dart';

part 'reviews_dao.g.dart';

@DriftAccessor(tables: [Reviews])
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

  Future<int> getReviewCount() async {
    final count = countAll();
    final query = selectOnly(reviews)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }
}
