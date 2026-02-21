import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../content/providers/content_providers.dart';
import '../../../domain/models/concept.dart';

part 'concepts_provider.g.dart';

class ConceptSection {
  final String title;
  final List<Concept> concepts;

  const ConceptSection({required this.title, required this.concepts});
}

@riverpod
Future<List<ConceptSection>> conceptsList(ConceptsListRef ref) async {
  final concepts = await ref.watch(allConceptsProvider.future);

  // Group concepts into sections by level
  final foundations = concepts.where((c) => c.level <= 2).toList();
  final jazzHarmony = concepts.where((c) => c.level > 2).toList();

  final sections = <ConceptSection>[];

  if (foundations.isNotEmpty) {
    sections.add(ConceptSection(title: 'Foundations', concepts: foundations));
  }
  if (jazzHarmony.isNotEmpty) {
    sections.add(ConceptSection(title: 'Jazz Harmony', concepts: jazzHarmony));
  }

  return sections;
}

@riverpod
Future<Concept> conceptById(ConceptByIdRef ref, String conceptId) async {
  final concepts = await ref.watch(allConceptsProvider.future);
  return concepts.firstWhere((c) => c.id == conceptId);
}
