import 'package:flutter_test/flutter_test.dart';
import 'package:jazz_piano_tools/domain/enums/answer_type.dart';
import 'package:jazz_piano_tools/domain/enums/exercise_mode.dart';
import 'package:jazz_piano_tools/domain/enums/input_type.dart';
import 'package:jazz_piano_tools/domain/models/models.dart';

void main() {
  group('Concept serialization', () {
    test('round-trips with all fields', () {
      const concept = Concept(
        id: 'c1',
        title: 'Triads',
        summary: 'Major, minor, dim, aug',
        bodyMarkdown: '# Triads\nContent here.',
        examples: [
          {'root': 'C', 'quality': 'major'}
        ],
        tags: ['harmony', 'chords'],
        level: 2,
        relatedExerciseIds: ['e1'],
        relatedCardDeckIds: ['d1'],
      );
      final json = concept.toJson();
      final restored = Concept.fromJson(json);
      expect(restored, equals(concept));
    });

    test('uses defaults for optional fields', () {
      final concept = Concept.fromJson({
        'id': 'c2',
        'title': 'Test',
        'summary': 'Sum',
        'bodyMarkdown': 'Body',
      });
      expect(concept.examples, isEmpty);
      expect(concept.tags, isEmpty);
      expect(concept.level, 1);
    });
  });

  group('Exercise serialization', () {
    test('round-trips with all fields', () {
      const exercise = Exercise(
        id: 'e1',
        title: 'Build Chord',
        mode: ExerciseMode.test,
        inputType: InputType.piano,
        generatorId: 'chord_build',
        config: {'keys': 'all'},
        tags: ['chords'],
        level: 1,
        estimatedMinutes: 3,
      );
      final json = exercise.toJson();
      final restored = Exercise.fromJson(json);
      expect(restored, equals(exercise));
    });
  });

  group('SrsCard serialization', () {
    test('round-trips correctly', () {
      const card = SrsCard(
        id: 'card1',
        deckId: 'd1',
        prompt: 'Play C major triad',
        expectedAnswer: 'C,E,G',
        answerType: AnswerType.pitch,
        metadata: {'root': 'C', 'quality': 'major'},
      );
      final json = card.toJson();
      final restored = SrsCard.fromJson(json);
      expect(restored, equals(card));
    });
  });

  group('Deck serialization', () {
    test('round-trips with nullable sourceConceptId', () {
      const deck = Deck(
        id: 'd1',
        title: 'Major Triads',
        tags: ['triads'],
        sourceConceptId: 'c1',
      );
      final json = deck.toJson();
      final restored = Deck.fromJson(json);
      expect(restored, equals(deck));
      expect(restored.sourceConceptId, 'c1');
    });

    test('handles null sourceConceptId', () {
      const deck = Deck(id: 'd2', title: 'Test');
      final json = deck.toJson();
      final restored = Deck.fromJson(json);
      expect(restored.sourceConceptId, isNull);
    });
  });

  group('SrsCardState serialization', () {
    test('round-trips with DateTime', () {
      final now = DateTime.utc(2025, 1, 15, 10, 30);
      final state = SrsCardState(
        cardId: 'card1',
        due: now,
        stability: 5.0,
        difficulty: 3.2,
        interval: 7,
        lapses: 1,
        reps: 5,
        state: 'review',
      );
      final json = state.toJson();
      final restored = SrsCardState.fromJson(json);
      expect(restored, equals(state));
      expect(restored.due, equals(now));
    });

    test('uses defaults for new card', () {
      final state = SrsCardState(
        cardId: 'card2',
        due: DateTime.utc(2025),
      );
      expect(state.stability, 0.0);
      expect(state.difficulty, 0.0);
      expect(state.interval, 0);
      expect(state.lapses, 0);
      expect(state.reps, 0);
      expect(state.state, 'new');
    });
  });

  group('Review serialization', () {
    test('round-trips correctly', () {
      final review = Review(
        id: 'r1',
        cardId: 'card1',
        timestamp: DateTime.utc(2025, 3, 10),
        rating: 3,
        responseTimeMs: 2500,
      );
      final json = review.toJson();
      final restored = Review.fromJson(json);
      expect(restored, equals(review));
    });
  });

  group('ExerciseAttempt serialization', () {
    test('round-trips with nullable key', () {
      final attempt = ExerciseAttempt(
        id: 'a1',
        exerciseId: 'e1',
        score: 0.85,
        durationSeconds: 120,
        key: 'C',
        timestamp: DateTime.utc(2025, 6, 1),
        details: {'correct': 8, 'total': 10},
      );
      final json = attempt.toJson();
      final restored = ExerciseAttempt.fromJson(json);
      expect(restored, equals(attempt));
      expect(restored.key, 'C');
    });

    test('handles null key', () {
      final attempt = ExerciseAttempt(
        id: 'a2',
        exerciseId: 'e1',
        score: 1.0,
        durationSeconds: 60,
        timestamp: DateTime.utc(2025),
      );
      expect(attempt.key, isNull);
      expect(attempt.details, isEmpty);
    });
  });
}
