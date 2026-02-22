import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../content/providers/content_providers.dart';
import '../features/settings/providers/settings_provider.dart';
import 'router.dart';
import 'theme.dart';

class JazzPianoToolsApp extends ConsumerWidget {
  const JazzPianoToolsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(contentBootstrapProvider);
    final themeMode = ref.watch(settingsProvider).maybeWhen(
          data: (settings) => _themeModeFrom(settings?.themeMode),
          orElse: () => ThemeMode.system,
        );
    return bootstrap.when(
      data: (_) {
        final router = ref.watch(routerProvider);
        return MaterialApp.router(
          title: 'Jazz Piano Tools',
          theme: appTheme,
          darkTheme: appDarkTheme,
          themeMode: themeMode,
          routerConfig: router,
        );
      },
      loading: () {
        return MaterialApp(
          title: 'Jazz Piano Tools',
          theme: appTheme,
          darkTheme: appDarkTheme,
          themeMode: themeMode,
          home: const _BootstrapScreen(
            title: 'Loading content…',
          ),
        );
      },
      error: (err, _) {
        return MaterialApp(
          title: 'Jazz Piano Tools',
          theme: appTheme,
          darkTheme: appDarkTheme,
          themeMode: themeMode,
          home: _BootstrapScreen(
            title: 'Failed to load content',
            error: err,
          ),
        );
      },
    );
  }

  ThemeMode _themeModeFrom(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}

class _BootstrapScreen extends ConsumerWidget {
  final String title;
  final Object? error;

  const _BootstrapScreen({
    required this.title,
    this.error,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isError = error != null;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isError)
                Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error)
              else
                const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (isError) ...[
                const SizedBox(height: 8),
                Text(
                  '$error',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(contentBootstrapProvider),
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
