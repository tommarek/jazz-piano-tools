import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/models/models.dart';

class ProgressionTierData {
  final String id;
  final String topic;
  final int tierNumber;
  final String title;
  final String description;
  final Map<String, dynamic> config;

  const ProgressionTierData({
    required this.id,
    required this.topic,
    required this.tierNumber,
    required this.title,
    this.description = '',
    required this.config,
  });

  factory ProgressionTierData.fromJson(Map<String, dynamic> json) {
    return ProgressionTierData(
      id: json['id'] as String,
      topic: json['topic'] as String,
      tierNumber: json['tierNumber'] as int,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      config: json['config'] as Map<String, dynamic>? ?? {},
    );
  }
}

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

  Future<List<ProgressionTierData>> loadProgressionTiers() async {
    final json = await rootBundle.loadString(
      'assets/content/progression/index.json',
    );
    final list = jsonDecode(json) as List;
    return list
        .map((e) =>
            ProgressionTierData.fromJson(e as Map<String, dynamic>))
        .toList();
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
