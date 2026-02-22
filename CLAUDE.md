# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

Flutter must be on PATH: `export PATH="/opt/homebrew/Caskroom/flutter/3.41.2/flutter/bin:$PATH"`

```bash
# Code generation (required after changing Drift tables/DAOs or Riverpod providers)
flutter pub run build_runner build --delete-conflicting-outputs

# Run all tests
flutter test

# Run a single test file
flutter test test/core/music/interval_test.dart

# Run tests matching a name
flutter test --name "ChordBuildGenerator"

# Analyze
flutter analyze
```

## Architecture

**Feature-first** layout under `lib/features/` (today, library, drill, srs, progression, settings, statistics, learn). Shared code lives in `lib/core/` (music theory, answer checkers, widgets), `lib/domain/` (Freezed models + enums), and `lib/database/` (Drift).

### Content Pipeline
JSON assets in `assets/content/` → `ContentLoader` parses them → `ContentRepository` syncs to SQLite → Riverpod providers expose to UI. The `contentBootstrapProvider` gates app routing until content is loaded.

### Exercise & Question System
Exercises have a `generatorId` that maps to a `QuestionGenerator` subclass via `resolveGenerator()` in `generator_registry.dart`. Each generator implements:
- `generate(Exercise, {count})` — random questions for test/drill mode
- `allItemIds(Exercise)` — universe of SRS-trackable items
- `generateForItems(Exercise, List<String> itemIds)` — targeted questions for SRS-driven practice

Topic mapping (`topicForGenerator()`): interval generators → `'intervals'`, chord generators → `'chords'`, shell/guide-tone → `'voicings'`, circle-of-fourths → `'circle-of-fourths'`.

### SRS (Spaced Repetition)
Two layers: `Cards`/`CardStates` tables for deck-based flashcards, and `ItemSchedules` table for exercise-item-level scheduling. Both use FSRS via `FsrsAdapter`. The `DrillProvider.startPracticeSession()` queries due items + new items (capped by `newCardsPerDay` setting) and generates targeted questions.

### Navigation
`GoRouter` with `StatefulShellRoute` for bottom nav (today, learn, library). Full-screen routes push over nav for drill, review, settings, statistics.

## Key Conventions

### Freezed 3.x
Must use `abstract class X with _$X` (not `class X with _$X`).

### Riverpod 2.x Codegen
Function providers use generated ref types: `Future<X> myProvider(MyProviderRef ref)`.

### Drift
- Generates data classes with same names as domain models. Use `import '...' as domain;` when both are needed in the same file.
- `isNotNull` conflicts with `flutter_test`. Use `hide isNotNull` on drift imports in tests.
- Use `driftDatabase(name: 'name')` API (not `DriftNativeDatabase`).
- **Never edit old migration blocks.** Add new `if (from < N)` blocks. Current schema version: 12.

### Music Theory Types
- `PitchClass`: 0–11 (C=0, C#/Db=1, ..., B=11)
- `Interval`: enum with `.semitones`, `.fullName`, `.symbol`
- `ChordQuality`: `.build(root)` returns `List<PitchClass>` chord tones
- `NoteName`: configurable sharp/flat display via `namerForStyle()` or `namerForRoot()`

### Question Metadata Convention
All generators put `topic`, `skill`, `itemId`, and `root` in `ExerciseQuestion.metadata`. The `itemId` is the SRS-trackable unit (e.g., interval name, chord quality name, or key-specific combo like `"ii-C"`).
