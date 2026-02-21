import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/models/models.dart';

class ContentLoader {
  Future<List<Concept>> loadConcepts() async {
    final json = await rootBundle.loadString(
      'assets/content/concepts/index.json',
    );
    final list = jsonDecode(json) as List;
    return list
        .map((e) => Concept.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Exercise>> loadExercises() async {
    final json = await rootBundle.loadString(
      'assets/content/exercises/index.json',
    );
    final list = jsonDecode(json) as List;
    return list
        .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Deck>> loadDecks() async {
    final json = await rootBundle.loadString(
      'assets/content/decks/index.json',
    );
    final list = jsonDecode(json) as List;
    return list
        .map((e) => Deck.fromJson(_extractDeck(e as Map<String, dynamic>)))
        .toList();
  }

  Future<List<SrsCard>> loadAllCards() async {
    final json = await rootBundle.loadString(
      'assets/content/decks/index.json',
    );
    final list = jsonDecode(json) as List;
    final cards = <SrsCard>[];
    for (final deckJson in list) {
      final deck = deckJson as Map<String, dynamic>;
      final deckCards = deck['cards'] as List? ?? [];
      for (final cardJson in deckCards) {
        cards.add(SrsCard.fromJson(cardJson as Map<String, dynamic>));
      }
    }
    return cards;
  }

  Map<String, dynamic> _extractDeck(Map<String, dynamic> json) {
    return {
      'id': json['id'],
      'title': json['title'],
      'tags': json['tags'],
      'sourceConceptId': json['sourceConceptId'],
    };
  }
}
