import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/today/screens/today_screen.dart';
import '../features/today/screens/review_session_screen.dart';
import '../features/today/screens/end_summary_screen.dart';
import '../features/learn/screens/learn_screen.dart';
import '../features/learn/screens/concept_detail_screen.dart';
import '../features/learn/screens/deck_review_screen.dart';
import '../features/library/screens/library_screen.dart';
import '../features/practice/screens/practice_hub_screen.dart';
import '../features/drill/screens/drill_screen.dart';
import '../features/drill/screens/learn_screen.dart';
import '../features/drill/screens/practice_screen.dart';
import '../features/drill/screens/session_builder_screen.dart';
import '../features/progression/screens/progression_screen.dart';
import '../features/statistics/screens/statistics_screen.dart';
import '../features/settings/screens/settings_screen.dart';

part 'router.g.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _todayNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'today');
final _learnNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'learn');
final _practiceNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'practice');
final _libraryNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'library');

@Riverpod(keepAlive: true)
GoRouter router(RouterRef ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/today',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ScaffoldWithBottomNav(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: _todayNavigatorKey,
            routes: [
              GoRoute(
                path: '/today',
                builder: (context, state) => const TodayScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _learnNavigatorKey,
            routes: [
              GoRoute(
                path: '/learn',
                builder: (context, state) => const LearnScreen(),
                routes: [
                  GoRoute(
                    path: 'concept/:conceptId',
                    builder: (context, state) {
                      final conceptId =
                          state.pathParameters['conceptId']!;
                      return ConceptDetailScreen(conceptId: conceptId);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _practiceNavigatorKey,
            routes: [
              GoRoute(
                path: '/practice-hub',
                builder: (context, state) => const PracticeHubScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _libraryNavigatorKey,
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
        ],
      ),
      // Full-screen routes (push over bottom nav)
      GoRoute(
        path: '/review',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ReviewSessionScreen(),
      ),
      GoRoute(
        path: '/session-builder/:exerciseId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final exerciseId = state.pathParameters['exerciseId']!;
          return SessionBuilderScreen(exerciseId: exerciseId);
        },
      ),
      GoRoute(
        path: '/learn/exercise/:exerciseId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final exerciseId = state.pathParameters['exerciseId']!;
          return ExerciseLearnScreen(exerciseId: exerciseId);
        },
      ),
      GoRoute(
        path: '/drill/:exerciseId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final exerciseId = state.pathParameters['exerciseId']!;
          return DrillScreen(exerciseId: exerciseId);
        },
      ),
      GoRoute(
        path: '/practice/:exerciseId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final exerciseId = state.pathParameters['exerciseId']!;
          return PracticeScreen(exerciseId: exerciseId);
        },
      ),
      GoRoute(
        path: '/progression/:topic',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final topic = state.pathParameters['topic']!;
          return ProgressionScreen(topic: topic);
        },
      ),
      GoRoute(
        path: '/statistics',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const StatisticsScreen(),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/deck-review',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final deckIds = (extra?['deckIds'] as List?)?.cast<String>();
          final questionCount = extra?['questionCount'] as int?;
          if (deckIds == null || questionCount == null) {
            return const Scaffold(
              body: Center(child: Text('Invalid deck review parameters')),
            );
          }
          return DeckReviewScreen(
            deckIds: deckIds,
            questionCount: questionCount,
            isRandom: extra?['isRandom'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: '/summary',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return EndSummaryScreen(
            cardsReviewed: extra['cardsReviewed'] as int? ?? 0,
            correctCount: extra['correctCount'] as int? ?? 0,
          );
        },
      ),
    ],
  );
}

class ScaffoldWithBottomNav extends StatelessWidget {
  const ScaffoldWithBottomNav({
    required this.navigationShell,
    super.key,
  });

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: 'Learn',
          ),
          NavigationDestination(
            icon: Icon(Icons.piano_outlined),
            selectedIcon: Icon(Icons.piano),
            label: 'Practice',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: 'Library',
          ),
        ],
      ),
    );
  }
}
