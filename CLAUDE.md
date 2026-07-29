# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

**Voicings** — a mobile-first spaced-repetition app for drilling jazz piano
voicings away from the keyboard. It trains **recall speed**, not physical
execution: the point is to take note-finding out of keyboard time so the
15–20 minutes at the piano goes on playing.

SvelteKit (static adapter) wrapped in Capacitor for iOS/Android. Fully offline —
no server, no account, no network. SQLite on device. One price, no in-app
purchases, no entitlement code.

A Flutter prototype of the same idea lived in this repo until July 2026; it is
preserved in history under the tag `flutter-prototype`.

## Commands

```bash
npm install
npm run dev             # vite dev server
npm run build           # static build into build/ — Capacitor's webDir
npm run check           # svelte-check; must be 0 errors
npm run test:unit       # vitest, incl. golden note-spelling snapshots
npm run test:unit -- -u # regenerate goldens (review every diff by hand)
npx playwright test     # e2e; builds the app itself
npm run sync            # build + cap sync
npm run ios             # build + sync + open Xcode
npm run apk             # build + sync + gradle assembleDebug
```

Simulator loop, no Xcode UI needed:

```bash
npm run build && npx cap sync ios
xcodebuild -project ios/App/App.xcodeproj -scheme App -configuration Debug \
  -destination 'id=<SIMULATOR_UDID>' -derivedDataPath /tmp/dd build
xcrun simctl install <SIMULATOR_UDID> /tmp/dd/Build/Products/Debug-iphonesimulator/App.app
xcrun simctl launch <SIMULATOR_UDID> online.markovi.voicings
```

The web build also ships as a PWA served by Caddy from the `selfhosted` stack;
deploying it means copying `build/` there (see that repo's CLAUDE.md).

## Architecture

```
src/lib/music/     the theory engine — pure, no I/O, no framework
  theory.ts        notes as (letter, alter, octave); diatonic interval arithmetic
  voicings.ts      chords, shells, rootless forms, ii–V–I chains
  theory-drills.ts extensions, diatonic degrees, drilled intervals
  cards.ts         the catalogue: CardSpec → stable id → CardView; STAGES
src/lib/audio/     Web Audio synth (no samples, no libraries)
src/lib/data/      queue, review, settings, stats, stages — all SQLite-backed
src/lib/scheduler/ FSRS wrapper + grading/mastery rules
src/lib/content/   the in-app reference layer
src/lib/db/        driver (wasm for web, native plugin for devices) + catalogue sync
src/routes/        today, session, progress, settings, reference
```

**Cards are generated, not stored.** `buildCatalogue()` produces all 1296 cards
deterministically; `cardId()` is a stable slug and the database keys review
history on it. **Changing an id orphans a user's history — don't.** Adding cards
is safe: `syncCatalogue()` inserts what is missing on launch (and backfills
`root_pitch_class` when a render fix changes it).

**Note spelling is the thing that must not regress.** Chords are built by
diatonic interval arithmetic so D♭ and C♯ stay distinct and C°7 spells its
seventh B♭♭. The whole deck is snapshotted in `tests/unit/__golden__/`; any diff
there is a spelling regression until proven otherwise.

## The deck and the path

Drills open in four stages, on demonstrated mastery or by hand in Settings.
This is pedagogy, not monetisation. `STAGES` lives in cards.ts;
`src/lib/data/stages.ts` evaluates the criteria and renders them as the
checklist on Today.

| Stage | Type | n | Asks |
|---|---|---|---|
| 1 Shells | `s2n` | 144 | symbol → tap the shell |
| | `n2s` | 60 | two lit keys, root marked → name a quality it fits |
| | `ivl` | 132 | tap an interval above a lit root |
| | `eint` | 132 | **hear** two notes → name the interval |
| 2 The ii–V–I | `chain` | 48 | all three shells, timed as one |
| | `vl` | 96 | where the guide tone goes |
| | `dia` | 84 | which chord is the ii / IV / vii |
| | `eqal` | 72 | **hear** a chord → name the quality |
| 3 Guide tones | `gt` | 72 | symbol → tap the 3rd and 7th |
| | `gtn` | 36 | two guide tones, 3rd marked → name a quality |
| | `gtc` | 48 | comp a ii–V–I in guide-tone voicings |
| 4 Rootless | `rootless` | 96 | four-note A/B forms, tapped bottom-up |
| | `rlc` | 48 | alternate A/B through a ii–V–I |
| | `ext` | 144 | find the ♭9 / ♯11 / 13 |
| | `mode` | 84 | which mode over which chord |

Stage criteria: 2 needs an automatic shell in all twelve keys; 3 needs 20
correct chains under 3.0s per chord; 4 needs 2.0s per chord plus every key at
least half automatic on shells.

### Adding a card type

Touch all of these or it will be silently undealable — there are tests for most,
but not all:
`CardType` union, `CARD_TYPES`, `STAGES` (STAGE_OF_TYPE derives from it),
`CARD_TYPE_LABEL`, `CARD_TYPE_HINT`, `TIME_TARGETS`, `CardSpec`, `cardId()`,
`parseCardId()`, `buildCatalogue()`, a `renderCard()` case (including `sound`),
the catalogue-count test, and the README deck table.

## Audio

A dependency-free Web Audio synth: the app ships no binary assets, so a sampled
piano is not an option. Three partials per note through a per-note lowpass and
an exponential decay.

Things that bit us and are pinned by tests:

- The `AudioContext` is created lazily on a user gesture (iOS blocks it
  otherwise) and resumed on **any** non-running state — WebKit has a
  non-standard `'interrupted'` state (phone call, Siri) that is not `'suspended'`
  and that lib.dom's type union omits.
- `stopAll()` must latch `gain.value` before `cancelScheduledValues`, or the
  param reverts to the last surviving event — the attack peak — and a decaying
  note snaps back to full volume. A voice whose attack has not started yet reads
  the GainNode default of **1.0**, not the envelope floor.
- Groups after the first are re-registered against the previous group
  (`voiceLed()` in cards.ts) so chain/vl/gtc/rlc actually voice-lead instead of
  leaping octaves. Every group gets a whole-group octave choice; only the
  guide-tone pairs (`gtc`, the one `invertible: true` call site) may also
  invert, because rotating a root-bearing voicing puts a root above its own 7th.
- The ear decks (`eint`, `eqal`) have **no** prompt but the sound, so they leave
  the deck entirely when `soundEnabled` is off.

## Conventions

- Svelte 5 runes (`$state`/`$derived`/`$props`), TypeScript strict.
- Comments explain **why** a non-obvious decision was made — never what the next
  line does. This code has been through a dozen adversarial review rounds; match
  the tone rather than adding narration.
- Answers are graded on **pitch class**, not spelling, so a one-octave keyboard
  works. Exceptions: rootless voicings are an ordered sequence, and cards whose
  notes do not determine one chord accept every consistent reading
  (`alsoAccept`).
- Card ids stay ASCII (`Db`, `Fs`); display goes through `prettyNoteName()` /
  `noteName()`, which emit ♭ ♯ glyphs.
- Speed rounds never write `card_state`, and are excluded from every median,
  accuracy and retention figure — a sprint is played faster than deliberate
  practice and would skew them. They DO count as practice, though: "done
  today", the week strip and the streak fold them back in at read time, because
  telling someone they did not practise on a day they did is its own bug.
- Day arithmetic goes through `addDays()` in queue.ts — never `ts ± 86_400_000`.
  DST days are 23 or 25 hours long and a fixed step corrupts the streak.
- All database transactions serialise through the driver: `conn.tx` is not
  reentrant, and a session's writes can overlap a page load.
- The session screen must fit a small phone **in both phases**. The reveal panel
  competes with the answer surface; several card types hide the now-redundant
  prompt on feedback to make room. There is an e2e test at 390×664.

## Testing

Three suites, all must pass:

- `npm run check` — 0 errors.
- **Unit** — the theory engine, the catalogue, scheduler/grading, the stage path,
  queue selection, a 630-day back-test of the real scheduler, and the golden
  spelling snapshots.
- **E2E** (Playwright) — every drill type, the path, feedback, "No idea", the
  reference sheet, mobile a11y, and viewport-fit regressions.

The e2e suite drives the app through `window.__voicings` test hooks, compiled in
only when `VITE_VT_TEST=1`, so store builds never contain them.

When a test fails after a deliberate change, fix the test to assert the new
intent — do not weaken it. Golden diffs get read note by note.
