import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'content/providers/content_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();
  final repo = container.read(contentRepositoryProvider);
  await repo.ensureContentLoaded();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const JazzPianoToolsApp(),
    ),
  );
}
