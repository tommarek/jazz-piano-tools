import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../content/providers/content_providers.dart';
import '../../../domain/models/concept.dart';
import '../../../domain/models/deck.dart';
import '../../../domain/models/exercise.dart';

part 'library_provider.g.dart';

enum LibraryFilterType { all, concepts, exercises, decks }

sealed class LibraryItem {
  String get id;
  String get title;
  List<String> get tags;
}

class ConceptItem implements LibraryItem {
  final Concept concept;

  const ConceptItem(this.concept);

  @override
  String get id => concept.id;
  @override
  String get title => concept.title;
  @override
  List<String> get tags => concept.tags;
}

class ExerciseItem implements LibraryItem {
  final Exercise exercise;

  const ExerciseItem(this.exercise);

  @override
  String get id => exercise.id;
  @override
  String get title => exercise.title;
  @override
  List<String> get tags => exercise.tags;
}

class DeckItem implements LibraryItem {
  final Deck deck;

  const DeckItem(this.deck);

  @override
  String get id => deck.id;
  @override
  String get title => deck.title;
  @override
  List<String> get tags => deck.tags;
}

@riverpod
class LibraryFilter extends _$LibraryFilter {
  @override
  LibraryFilterType build() => LibraryFilterType.all;

  void setFilter(LibraryFilterType filter) {
    state = filter;
  }
}

@riverpod
class LibrarySearch extends _$LibrarySearch {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }
}

@riverpod
Future<List<LibraryItem>> libraryItems(LibraryItemsRef ref) async {
  final filter = ref.watch(libraryFilterProvider);
  final search = ref.watch(librarySearchProvider).toLowerCase();

  final items = <LibraryItem>[];

  if (filter == LibraryFilterType.all ||
      filter == LibraryFilterType.concepts) {
    final concepts = await ref.watch(allConceptsProvider.future);
    items.addAll(concepts.map((c) => ConceptItem(c)));
  }

  if (filter == LibraryFilterType.all ||
      filter == LibraryFilterType.exercises) {
    final exercises = await ref.watch(allExercisesProvider.future);
    items.addAll(exercises.map((e) => ExerciseItem(e)));
  }

  if (filter == LibraryFilterType.all ||
      filter == LibraryFilterType.decks) {
    final decks = await ref.watch(allDecksProvider.future);
    items.addAll(decks.map((d) => DeckItem(d)));
  }

  if (search.isEmpty) return items;

  return items.where((item) {
    return item.title.toLowerCase().contains(search) ||
        item.tags.any((t) => t.toLowerCase().contains(search));
  }).toList();
}
