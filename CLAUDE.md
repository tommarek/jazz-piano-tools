# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

**Voicings** — a mobile-first spaced-repetition app for drilling jazz piano voicings
away from the keyboard. SvelteKit (static) wrapped in Capacitor for iOS/Android,
fully offline, SQLite on device. One price, no in-app purchases.

A Flutter prototype of the same idea lived here until 2026-07; it is preserved in
git history under the tag `flutter-prototype`.

## Commands

```bash
npm install
npm run dev             # vite dev server
npm run build           # static build into build/ — Capacitor's webDir
npm run check           # svelte-check; must be 0 errors before committing
npm run test:unit       # vitest, incl. golden note-spelling snapshots
npm run test:unit -- -u # regenerate goldens (review every diff by hand)
npx playwright test     # e2e against the built app
npm run sync            # build + cap sync
npm run ios             # build + sync + open Xcode
npm run apk             # build + sync + gradle assembleDebug
```

Simulator loop (no Xcode UI needed):

```bash
npm run build && npx cap sync ios
xcodebuild -project ios/App/App.xcodeproj -scheme App -configuration Debug \
  -destination 'id=<SIMULATOR_UDID>' -derivedDataPath /tmp/dd build
xcrun simctl install <SIMULATOR_UDID> /tmp/dd/Build/Products/Debug-iphonesimulator/App.app
xcrun simctl launch <SIMULATOR_UDID> online.markovi.voicings
```

## Architecture

```
src/lib/music/     the theory engine — pure, no I/O
  theory.ts        notes as (letter, alter, octave); diatonic interval arithmetic
  voicings.ts      chords, shells, rootless forms, ii–V–I chains
  theory-drills.ts extensions, diatonic degrees, drilled intervals
  cards.ts         the catalogue: CardSpec → stable id → CardView, STAGES
src/lib/audio/     Web Audio synth (no samples, no libraries)
src/lib/data/      queue, review, settings, stats, stages (all SQLite-backed)
src/lib/scheduler/ FSRS wrapper + grading/mastery rules
src/lib/content/   the in-app reference layer
src/routes/        today, session, progress, settings, reference
```

**Cards are generated, not stored.** `buildCatalogue()` produces every card
deterministically; `cardId()` is a stable slug and the database keys review
history on it. Changing an id orphans a user's history — don't. Adding cards is
safe: `syncCatalogue()` inserts what is missing on launch.

**Note spelling is the thing that must not regress.** Chords are built by
diatonic interval arithmetic so D♭ and C♯ stay distinct and C°7 spells B♭♭. The
whole deck is snapshotted in `tests/unit/__golden__/`; any diff there is a
spelling regression until proven otherwise.

**The path.** Drills open in four stages (`STAGES` in cards.ts, evaluated by
`src/lib/data/stages.ts`) — shells → ii–V–I → guide-tone voicings → rootless &
colours. Stages open on demonstrated mastery or by hand in Settings. This is
pedagogy, not monetisation.

## Conventions

- Svelte 5 runes (`$state`/`$derived`/`$props`), TypeScript strict.
- Comments explain **why** a non-obvious decision was made — never what the next
  line does. This codebase has been through many review rounds; match the tone.
- Answers are graded on **pitch class**, not spelling, so a one-octave keyboard
  works. The exception is rootless voicings, graded as an ordered sequence.
- Speed rounds never write `card_state` and are excluded from every median,
  accuracy and retention statistic.
- Day arithmetic goes through `addDays()` in queue.ts — never `ts ± 86_400_000`
  (DST days are 23 or 25 hours long).
- All database transactions serialise through the driver: `conn.tx` is not
  reentrant.

## Testing

Three suites, all must pass:
- `npm run check` — 0 errors.
- **Unit** — the theory engine, the catalogue, scheduler/grading, the stage path,
  a 630-day back-test of the scheduler, and the golden spelling snapshots.
- **E2E** (Playwright) — every drill type, the path, feedback, "No idea", the
  reference sheet, mobile a11y, and viewport-fit regressions.

The e2e suite drives the app through `window.__voicings` test hooks, compiled in
only when `VITE_VT_TEST=1`.
