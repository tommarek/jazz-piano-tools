import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jazz_piano_tools/app/theme.dart';

/// Minimal navigation test that verifies the 3-tab bottom nav works
/// without needing the full provider tree.
void main() {
  Widget buildTestApp() {
    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
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
          },
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/today',
                builder: (_, _) => Scaffold(
                  appBar: AppBar(title: const Text('Today')),
                  body: const Center(child: Text('Today')),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/learn',
                builder: (_, _) => Scaffold(
                  appBar: AppBar(title: const Text('Learn')),
                  body: const Center(child: Text('Learn')),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/library',
                builder: (_, _) => Scaffold(
                  appBar: AppBar(title: const Text('Library')),
                  body: const Center(child: Text('Library')),
                ),
              ),
            ]),
          ],
        ),
      ],
    );

    return ProviderScope(
      child: MaterialApp.router(
        routerConfig: router,
        theme: appTheme,
      ),
    );
  }

  group('Bottom navigation', () {
    testWidgets('renders all three navigation destinations',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsWidgets);
      expect(find.text('Learn'), findsWidgets);
      expect(find.text('Library'), findsWidgets);
    });

    testWidgets('starts on Today tab', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Today'), findsOneWidget);
    });

    testWidgets('tapping Learn tab shows Learn screen',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.school_outlined));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Learn'), findsOneWidget);
    });

    testWidgets('tapping Library tab shows Library screen',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.library_music_outlined));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);
    });

    testWidgets('can navigate back to Today from another tab',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.school_outlined));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Learn'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.today_outlined));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Today'), findsOneWidget);
    });
  });
}
