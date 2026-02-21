import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/today/screens/today_screen.dart';
import '../features/today/screens/review_session_screen.dart';
import '../features/today/screens/end_summary_screen.dart';
import '../features/learn/screens/learn_screen.dart';
import '../features/learn/screens/concept_detail_screen.dart';
import '../features/library/screens/library_screen.dart';
import '../features/drill/screens/drill_screen.dart';
import '../features/drill/screens/practice_screen.dart';

part 'router.g.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _todayNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'today');
final _learnNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'learn');
final _libraryNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'library');

@riverpod
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
                    path: ':conceptId',
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
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: 'Library',
          ),
        ],
      ),
    );
  }
}
