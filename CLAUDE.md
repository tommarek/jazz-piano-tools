# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

**Comp** — a mobile-first spaced-repetition app for drilling jazz piano away
from the keyboard. (Repo name and bundle id still say `voicings`, which predates
the rename; the two sections are **Theory** and **Ear**, and renaming a
published app's id would break it, so they stay.) It trains **recall speed**, not physical
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
src/lib/data/      queue, review, settings, stats, stages, decks, browse — SQLite-backed
src/lib/scheduler/ FSRS wrapper + grading/mastery rules
src/lib/content/   the in-app reference layer
src/lib/db/        driver (wasm for web, native plugin for devices) + catalogue sync
src/routes/        today, ear, session, progress, settings, reference, deck/[slug]
```

**Cards are generated, not stored.** `buildCatalogue()` produces all 972 cards
deterministically; `cardId()` is a stable slug and the database keys review
history on it. **Changing an id DELETES a user's history — don't.** The card
leaves the catalogue, and `syncCatalogue()` purges the rows of anything the
catalogue no longer generates; there is no server-side copy. The whole id list
is a golden (`tests/unit/__golden__/ids.txt`), so the diff is reviewable: new
lines are a new drill, changed or missing ones are somebody's practice. Adding cards
is safe: `syncCatalogue()` inserts what is missing on launch (and backfills
`root_pitch_class` when a render fix changes it).

**Note spelling is the thing that must not regress.** Chords are built by
diatonic interval arithmetic so D♭ and C♯ stay distinct and C°7 spells its
seventh B♭♭. The whole deck is snapshotted in `tests/unit/__golden__/`; any diff
there is a spelling regression until proven otherwise.

## Two sections

The app is split in half, and the halves share only the database and the
scheduler. **Theory** (`/`) is everything read: symbol → notes, chains, voicings, and the
intervals, diatonic harmony and modes under them.
**Ear** (`/ear`) is hearing: `eint` and `eqal`. `SECTION_OF_TYPE` in cards.ts is
the mapping, and everything downstream derives from it — a session never crosses
the line, the counts on each screen are its own, and the Progress figures are
computed over one section at a time. Reading a chord and hearing one run at
different speeds; one median over both described neither.

Each section has its own ladder, numbered from 1, and **a stage number only
means anything next to its section**: `STAGES` (three, theory) and `EAR_STAGES`
(two, ear), gated by `settings.unlockedStages` and `settings.earUnlockedStages`
respectively. `openStages(settings, section)` is the only correct way to ask.
The ear gate is **accuracy** (80% over 20 non-sprint `eint` attempts), not speed:
perception stays slow long after it is reliable.

Ear cards used to live in theory stages 1 and 2, so `getSettings()` migrates a
blob with no `earUnlockedStages` off the old theory stage — otherwise the split
silently takes qualities-by-ear away from anyone who had earned it.

## The deck and the path

Theory drills open in three stages, on demonstrated mastery or by hand in
Settings. This is pedagogy, not monetisation. `STAGES` lives in cards.ts;
`src/lib/data/stages.ts` evaluates the criteria and renders them as the
checklist on Today, and `evaluateEarPath()` does the same for the ear section.

The path is guide-tone-first. Root-based shells (s2n, n2s, the shell chains,
vl) were CUT in July 2026: the 3–7 pair is the thing worth automating and the
root belongs to the bass player. `syncCatalogue()` deletes their rows and
history on launch — a deliberate purge, documented there. Do not resurrect the
old ids; the new chain deliberately took a different id shape (`chain:C`, not
`chain:C:737`) so it starts unscheduled.

| Stage | Type | n | Asks |
|---|---|---|---|
| 1 Guide tones | `gt` | 72 | symbol → tap the 3rd and 7th |
| | `gtn` | 36 | two guide tones, 3rd marked → name a quality |
| | `ivl` | 132 | tap an interval above a lit root |
| 2 The ii–V–I | `chain` | 24 | the guide tones of all three chords, timed as one |
| | `gtc` | 48 | comp one transition: one note holds, one moves |
| | `dia` | 84 | which chord is the ii / IV / vii |
| 3 Rootless | `rootless` | 96 | four-note A/B forms, tapped bottom-up |
| | `rlc` | 48 | alternate A/B through a ii–V–I |
| | `ext` | 144 | find the ♭9 / ♯11 / 13 |
| | `mode` | 84 | which mode over which chord |

Stage criteria: 2 needs an automatic guide-tone pair in all twelve keys; 3
needs 20 correct chains under 2.0s per chord plus every key at least half
automatic on guide tones. `pathVersion` in settings renumbers four-stage-era
blobs (old 3→2, 4→3). The marker is only persisted by the next save, so that
mapping re-runs on every load until then and has to stay idempotent — it maps
the stored number, it never decrements the live one.

The ear section, on its own two-stage path:

| Stage | Type | n | Asks |
|---|---|---|---|
| 1 Intervals by ear | `eint` | 132 | **hear** two notes → name the interval |
| 2 Qualities by ear | `eqal` | 72 | **hear** a chord → name the quality |

Ear stage 2 opens at 80% over 20 heard intervals. Both ear decks leave the deck
entirely when `soundEnabled` is off — they have no prompt but the sound — which
is why `/ear` replaces itself with a "sound is off" panel rather than offering
an empty Start.

## Decks

A session can be pointed at one part of the catalogue: a whole section, a stage
of that section's path, or a single drill type. Every deck belongs to exactly
one section (`deckSection()`), and `ALL_DECK` is the theory section — a deck
slug from before the split (`?deck=all`) resolves there. `src/lib/data/decks.ts` owns the model; it is a *filter*
and nothing else, so review history stays keyed on the card id and a card's
schedule is identical whichever deck dealt it.

- The mixed queue is still the default and still the primary button. Blocking
  one drill feels productive and transfers worse — the picker is worded as the
  escape hatch it is, and a stage deck (the three or four drills of one stage)
  is offered above a single drill deliberately.
- `liveDeckTypes()` is the one place the gates compose, and **which gates apply
  depends on how the deck was chosen**. A *section* deck is the daily mix, so
  the path applies: an unopened stage stays out. A stage or drill deck was
  named by the learner, so the path does NOT apply — it is a suggested order,
  not a lock, and Settings could always open any stage by hand. A picker whose
  rows refuse to deal is the suggestion behaving like a wall.
- What no deck can override is a drill switched off, or an ear drill with sound
  off: those have no card to show, which is what `deckBlock()` reports.
  `deckAhead()` is the softer state — drillable now, but out of the mix until
  its stage opens, which the picker labels "ahead".
- `parseDeckSlug()` falls back to the everything deck on anything unrecognised.
  A link outlives the version that wrote it.
- `/deck/<slug>` browses a deck: its cards grouped by drill, with state, due
  date and median, filterable by due/weak/automatic. `src/lib/data/browse.ts`
  draws it from the same `liveDeckTypes` the queue uses, so a switched-off
  drill is absent from both. It is the **one screen that shows prompt and
  answer together**, deliberately: it is for checking a deck, not for drilling
  it, and it is not on the way to a session. Ear rows carry the sound rather
  than a description of it, because that is what their question is. Its loader
  404s on an unknown slug rather than falling back to another deck the way a
  session does.
- The session summary carries a switcher over the same section's decks, because
  the nav is hidden while drilling and the end of a session is the only place
  "what next" can be asked without interrupting a card.
- `deckCounts()` is one pass over the card table for a whole section's rows —
  fourteen on Today, five on Ear. It applies the quality switches as well as
  the type ones, so a row can never advertise cards its own session would then
  refuse to deal; `deckBlock`'s third reason, `'qualities'`, is added there
  because settings alone cannot see it. Its
  `due` and `size` are additive across decks; **`new` is not** — the new-card
  budget belongs to the day, so every row is counted as if it were the one you
  picked. Today states the shared budget once, under the list, rather than
  repeating it per row where three stage decks would advertise it three times.
- That budget is **per section**: `newCardsIntroducedToday()` counts only the
  reviewed section's cards. One pool made the halves compete, and a learner who
  opens Theory first spent the whole day's allowance there every day — so `/ear`
  never introduced a first `eint` card and its 20-attempt gate could never be
  reached.

### Adding a card type

Touch all of these or it will be silently undealable, or dealt in the wrong
half of the app — there are tests for most, but not all:
`CardType` union, `CARD_TYPES`, `EAR_TYPES` if it is an ear drill (it is what
`SECTION_OF_TYPE` reads, and a drill missing from it is dealt in theory
sessions and counted in theory medians), its section's ladder — `STAGES` or
`EAR_STAGES`, both of which `STAGE_OF_TYPE` derives from — `CARD_TYPE_LABEL`,
`CARD_TYPE_HINT`, `TIME_TARGETS`, `CardSpec`, `cardId()`, `parseCardId()`,
`buildCatalogue()`, a `renderCard()` case (including `sound`), the
catalogue-count test, and the README deck table.

`qualityActive()` in queue.ts as well, if the type stores anything in the
`quality` column that is not a `Quality` — the `as never` cast there means a
class name like `gtn`'s compiles fine and then matches no active quality, which
takes the drill out of the deck entirely. A progression card also belongs in
`PROGRESSION_TYPES`, so it is gated on every chord it contains, and one that
names its chord by scale degree in `DEGREE_TYPES`, so it is gated on that
degree's quality — `dia`'s whole answer is root + quality, and no column holds
it.

## Audio

A dependency-free Web Audio synth. The app ships no audio assets at all — the
only sizeable binary in `static/` is an 85 KB font; a usable soundfont is tens
of megabytes, so a sampled piano is not an option and never will be. Each note is one `PeriodicWave` — a struck-string
partial series, notched at the 7th where the hammer strikes — sounded by two
slightly detuned oscillators, through a per-note lowpass whose cutoff falls
faster than the note does, under a two-stage decay. Register drives all of it:
partial count, attack, ring time.

Things that bit us and are pinned by tests:

- The cutoff is an automated param, not a value. Every fake AudioContext in the
  suite has to schedule on it (`tests/unit/piano-stop.test.ts`,
  `audio-unavailable.test.ts`, `gateAudioBehindAGesture` in the e2e theory
  spec) — a fake that only carries `frequency.value` throws inside
  `playSequence`, which catches, returns false, and shows an ear card as "No
  sound on this device".
- A `PeriodicWave` belongs to its context, so the cache is dropped whenever one
  is built; a context without `createPeriodicWave` caches the null too and
  falls back to a triangle.

- The `AudioContext` is created lazily on a user gesture (iOS blocks it
  otherwise) and resumed on **any** non-running state — WebKit has a
  non-standard `'interrupted'` state (phone call, Siri) that is not `'suspended'`
  and that lib.dom's type union omits.
- `stopAll()` must latch `gain.value` before `cancelScheduledValues`, or the
  param reverts to the last surviving event — the attack peak — and a decaying
  note snaps back to full volume. An AudioParam reports the node default of
  **1.0** until its first scheduled event actually arrives, which is why the
  intrinsic `gain.value` is floored at **0.0001** when the voice is built and
  why `stopAll` cuts a voice whose onset is still in the future instead of
  ramping it. `piano-stop.test.ts` pins both halves.
- Groups after the first are re-registered against the previous group
  (`voiceLed()` in cards.ts) so chain/gtc/rlc actually voice-lead instead of
  leaping octaves. Every group gets a whole-group octave choice; only the
  guide-tone pairs (chain and `gtc`, the `invertible: true` call sites) may
  also invert. `rlc` may not: rotating a rootless voicing by two voices turns
  an A form into the B form — the same pitch classes in the other order — so
  it would sound the opposite form from the one the card asks for.
- The ear decks (`eint`, `eqal`) have **no** prompt but the sound, so they leave
  the deck entirely when `soundEnabled` is off.

## The look

The materials of a piano rather than the palette of a dashboard, because the
subject is a piano and the screen is held next to one in the evening. The tokens
live in `src/app.css`, and a screen reaching past them for a raw hex is the bug —
a chart series passes `var(--color-brass)`, not the value behind it. Two palettes
are deliberately local: the keyboard's key materials, ivory and ebony rather than
any token because the keys are the one light surface in the app, and the ordered
ramps on Progress, which are steps of one hue rather than named colours. Under
the token scale, `text-[9px]`/`[10px]`/`[11px]` are the small print — legends,
per-row stats, the "ahead" tag. Inline sizes otherwise are the two display
figures (Today's headline, a card's symbol) and `font-size:0.8125rem` on a
filled or eyebrow button, which sits between Tailwind's `xs` and `sm`; anything
else belongs on the scale.

- **Ebony ground, ivory ink, brass for anything to act on, felt for a miss,
  sage for a hit.** Brass fills carry *ebony* text (`--color-on-brass`), never
  white — a warm mid-tone under white text is 2.2:1. There is exactly one
  filled button per screen; everything else is a rule or an outline.
- **Sections are separated by rules, not fenced in cards** (`.rule`,
  `.rule-brass`). Bordered boxes survive only where something really is a
  discrete object: the feedback verdict, the stage-unlocked banner, an error.
  Those are a coloured rule down the left edge, like a mark in a margin.
- **One family, two widths.** Archivo variable, latin subset, self-hosted at
  `static/fonts/`. Expanded caps at 10px with 0.2em tracking are the structural
  voice (`.eyebrow`): every section label, tab, nav item and button wears it and
  nothing else does. Figures go through `.figure` — tabular, so a column of
  times does not jitter. Never put `.figure` on a phrase, only on the number.
  The subset includes the arrows the titles are full of; ♭ ♯ ♪ ▶ ✕ are not in
  Archivo at all and come from the platform, which is the one place the app's
  type is not its own — see the note in `app.css` before adding a symbol.
- **Chord symbols are engraved, not printed** — `ChordSymbol.svelte`, used
  everywhere a symbol appears. Root at full size, accidental raised and tucked
  in, quality lifted to a superscript. Its markup is one unbroken line under a
  `prettier-ignore` on purpose: split across lines or laid out as flex items,
  the browser reads "B♭maj7" back as "B ♭ maj7", which is what a screen reader
  announces and what the answer-text assertions see.
- **Keyboard states carry meaning, and only one of them is a hue you can lose.**
  A chosen key inverts (white → ebony, black → ivory) so selection survives any
  colour vision; brass is the app telling you something, sage is right, felt is
  wrong.
- **Charts:** mastery is an *ordered* scale, so it is one hue light-to-dark, not
  four named colours — sage against brass measures ΔE 4.9 under protanopia and
  10.4 with full colour vision, i.e. one colour to a lot of people. Validate any
  categorical palette with the dataviz skill's `validate_palette.js` before
  shipping it; every step carries a label and a count regardless.

## Conventions

- Svelte 5 runes (`$state`/`$derived`/`$props`), TypeScript strict.
- Comments explain **why** a non-obvious decision was made — never what the next
  line does. This code has been through a dozen adversarial review rounds; match
  the tone rather than adding narration.
- Answers are graded on **pitch class**, not spelling. The keyboard is an
  octave and a half (G–E, C home) plus a half F♯ clipped at the left edge so
  the outermost G keeps a piano's black-key pattern instead of reading as a C.
  Flanking keys carry `data-flank-pc` and mirror the pc states the APP asserts
  (given, reveal, wrong, previous); the learner's own selection lights only
  the copy that was tapped (`origins` in Keyboard.svelte). Only the home
  octave carries `data-pc` — tests and badges key on that. Input commits on pointer RELEASE
  with a drag bubble naming the key under the finger; keyboard-only activation
  still works via click detail 0. Keys are deliberately narrower than 44px
  (tall instead); the a11y specs assert fit, not width. Exceptions to
  set-grading: rootless voicings are an ordered sequence, and cards whose
  notes do not determine one chord accept every consistent reading
  (`alsoAccept`).
- The chain keeps the previous chord's taps lit on the keyboard (`previous`
  prop — a dimmed fill, luminance not hue, one step quieter than a live
  selection): the next chord is played from where the hand is, and a keyboard
  wiped blank between chords hid the one relationship the drill teaches. Those
  ghosts are the learner's own answer, not the truth, which is why only a
  multi-step card has them — gtc and rlc are one step each and show the chord
  they move *from* as `given`, in brass, because there it is the truth. On reveal, every same-width multi-group sound (chain, gtc,
  rlc) gets `VoiceLeading.svelte` — a graph of the registered `voiceLed()`
  midi, one brass line per voice with held/½/1 labels. Every drill that draws it
  deals rootless or guide-tone voicings, so no voice moves more than a whole
  tone (pinned in audio.test.ts) and there is no leaping root to contrast
  against any more. Same data the ♪ button plays, so sound and graph
  cannot disagree; the graph stands **instead of** the prose rationale, which
  is the same sentence and costs the keyboard its bottom third at 390×664.
- The `instantAnswer` setting submits on the pick, and only for the three inputs
  a single tap finishes (`quality-name`, `mode-name`, `interval-name`) — the
  `oneTapCard` list in the session page. Anything asking for a root as well has
  a half-made answer that must not be graded. Off by default, and off for every
  settings blob written before it existed: switching it on for someone who never
  asked turns their stray taps into wrong answers.
- Card ids stay ASCII (`Db`, `Fs`); display goes through `prettyNoteName()` /
  `noteName()`, which emit ♭ ♯ glyphs.
- Speed rounds never write `card_state`, and are excluded from every median,
  accuracy and retention figure — a sprint is played faster than deliberate
  practice and would skew them. They DO count as practice, though: "done
  today", the week strip and the streak fold them back in at read time, because
  telling someone they did not practise on a day they did is its own bug.
- **Calendar** arithmetic goes through `addDays()` in queue.ts — never
  `ts ± 86_400_000`. DST days are 23 or 25 hours long and a fixed step corrupts
  the streak, the week strip and the daily_stats keys. Interval arithmetic is
  the exception and is deliberately fixed-24h: FSRS's own days are, so
  `capUntilAutomatic` stays in the same unit the model uses rather than snapping
  a due time to local midnight.
- All database transactions serialise through the driver: `conn.tx` is not
  reentrant, and a session's writes can overlap a page load.
- The session screen must fit a small phone **in both phases**, and the sticky
  Next bar is opaque, so "fits" means the keyboard clears its top edge too. The
  reveal panel competes with the answer surface, and four things give way on
  feedback: the instruction always, the title where something below repeats it
  (`titleStepsAside` — chips, graph labels, or dia's rationale), the prose
  rationale where the graph draws it, and the keyboard, which drops to 140px
  because on the reveal it is read rather than tapped. A quality-name card's
  keyboard *is* the prompt, so it is compact while answering and removed
  outright on the reveal. There are e2e
  tests at 390×664 for every drill that draws a graph, and one at 375×667 for
  `gtn`, the only drill that stacks a keyboard on a picker.

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
