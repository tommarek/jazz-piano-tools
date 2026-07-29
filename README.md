# Voicings

> Repo name `voicing-trainer`; the app calls itself **Voicings** everywhere users see it.

A mobile-first app for drilling jazz piano shell voicings away from the keyboard.
It trains **recall speed**, not physical execution — the point is to take
note-finding out of keyboard time so the 15–20 minutes at the piano goes on
playing rather than working out which notes to press.

**Fully offline. No server, no account, no network.** The database is SQLite on
the device; nothing you do leaves the phone. One codebase produces three things:

| Target | How |
|---|---|
| iOS app | Capacitor shell, native SQLite |
| Android app | Capacitor shell, native SQLite |
| Web PWA | same bundle, SQLite compiled to WASM, persisted to IndexedDB |

## Why it is built the way it is

Every feature traces to one of these, and anything that didn't was cut.

| Principle | How it shows up |
|---|---|
| Retrieval practice | Every card asks you to produce the answer before revealing it. A chord symbol and its notes are never shown together. |
| Spaced repetition | FSRS (`ts-fsrs`) decides what is due, at 90% target retention. |
| Interleaving | The queue is shuffled and then actively pulled apart so neighbours don't share a root or a card type. |
| Variable practice | The same chord is asked in isolation, in a ii–V–I, from notes, and as a voice-leading move. |
| Desirable difficulty | A timer bar that turns amber past your baseline and red past double it. |
| Generation effect | Answers are tapped on a keyboard or built from a full grid — never picked from four options. |
| Short, frequent sessions | Hard-capped at 6 minutes / 30 cards by default. |
| Immediate feedback | Correct answer, your time against your median, and a one-line reason, straight after the attempt. |
| Motor imagery | Visualise-then-place blanks the keyboard for a few seconds first. |

## Response time is the signal

Getting a shell right after six seconds of thinking is the exact state the app
exists to fix, so slow-and-correct is not treated as learned:

- **Grades are derived, not self-rated.** Wrong → Again. Correct but slower than
  2× your rolling median for that card → Hard. Faster than 0.6× → Easy.
  Otherwise Good. A card with no history is judged against its type's baseline.
- **Mastery has a time gate.** *Familiar* needs 3 consecutive correct;
  *automatic* needs 5 **and** a median under the type's target (2.0s for a single
  chord, 6.0s for a three-chord chain).
- **Non-automatic cards are capped at a 21-day interval.** FSRS optimises for
  eventual recall and will happily park a correct-but-slow card for months; that
  is precisely the card that needs to come back. The back-test caught this — the
  worst starvation gap was 148 days before the cap was added.
- **New cards only fill space the due pile leaves.** With 1296 cards and a 21-day
  ceiling on anything not yet automatic, introducing 8 a day regardless of
  backlog buries you. The back-test caught this one too.

The headline number on the Today screen is the median response time on ii–V–I
chain cards, per chord. Under ~2s means shells are automatic.

## The deck — 1296 cards

| Type | Count | Prompt → answer |
|---|---|---|
| `s2n` symbol → notes | 144 | "Dm7, root–7 shell" → tap two keys |
| `n2s` notes → symbol | 60 | Two lit keys, root marked → name a quality it could be |
| `chain` ii–V–I | 48 | A key → all three shells, scored and timed as one unit |
| `vl` voice-leading | 96 | A shell and the next chord → tap where the guide tone goes |
| `gt` symbol → guide tones | 72 | "Dm7" → tap the 3rd and 7th |
| `gtn` guide tones → symbol | 36 | Two lit keys, 3rd marked → name a quality the pair fits |
| `gtc` guide-tone comping | 48 | Previous pair lit → tap the next chord's two notes |
| `rootless` A/B forms | 96 | "Dm7, B form" → tap four notes **bottom-up** |
| `rlc` rootless comping | 48 | "Dm7 in A form" → tap G7's B form bottom-up |
| `ext` extensions & alterations | 144 | "The ♯9 of A7" → tap it |
| `dia` diatonic harmony | 84 | "The ii of D♭?" → name root + quality |
| `ivl` intervals | 132 | "A diminished 5th above B♭" → tap it |
| `mode` scales & modes | 84 | "Bm7 in A major" → pick from all seven modes |
| `eint` intervals by ear | 132 | Two notes played → name the interval |
| `eqal` qualities by ear | 72 | A four-note chord played → name the quality |

Answers are graded on **pitch class**, not absolute pitch. That is what lets the
keyboard be one octave, which is what lets the keys be 44px on a phone. The one
exception is rootless voicings — see below.

### Where the music forced a design change

1. **Notes → symbol accepts any consistent chord.** Two notes do not
   determine a chord: Dm7 and Dm7♭5 share their third, and D7 and Dm7 share their
   seventh. So the drill asks which chord the shell *could* belong to, and every
   quality it is consistent with is graded correct.
2. **The root is marked on the prompt keyboard.** Without it, two lit keys are
   still ambiguous: {D♭, E} is a minor 3rd over D♭ and equally a diminished 7th
   over E.
3. **Rootless answers are graded as a sequence, not a set.** The A and B forms of
   a chord are the same four pitch classes — 3-5-7-9 versus 7-9-3-5 — so on a
   one-octave keyboard nothing but the tap order can tell them apart. You tap the
   voicing bottom-up and the keys number themselves as you go.
4. **Diatonic answers are graded by pitch class.** The IV of G♭ is C♭ and the vii
   of B is A♯; neither is on the root grid. The feedback shows the real spelling.
5. **The ear drills never show or ask the root.** An interval is a distance and a
   quality is a colour; both survive transposition, so the card varies the
   starting note across all twelve without ever naming it. The same interval from
   a different root is a fresh rep for the ear, not a duplicate card.

### Rootless voicings

A form is 3rd-on-the-bottom, B form is the same voicing with the top two voices
moved underneath:

| | A form | B form |
|---|---|---|
| maj7 | 3–5–7–9 | 7–9–3–5 |
| m7 | ♭3–5–♭7–9 | ♭7–9–♭3–5 |
| 7 | 3–13–♭7–9 | ♭7–9–3–13 |
| m7♭5 | ♭3–♭5–♭7–1 | ♭7–1–♭3–♭5 |

Dominants take the 13th rather than the 5th: on a V chord the 5th is dead weight.

They sit at the top of the **path** — four stages that open by demonstrated
mastery (or by hand in Settings): shells first, then the ii–V–I, then guide-tone
voicings, then rootless. Rootless opens at a median under 2.0s per chord over at
least 20 correct major chains with every key at least half automatic on shells.
The Today screen always shows the next stage and what it needs.

### Minor ii–V–i

iiø7 – V7 – i m(maj7). The V comes from the harmonic minor so it has a real
leading tone; the tonic is m(maj7) because m6 has no seventh for a shell to use.

Minor keys are not spelled like major ones: C♯ minor rather than D♭ minor, but
**A♭ minor rather than G♯ minor**, because G♯ minor's V and i both want F𝄪.

In `3-7-3` the 7th of V falls a **whole tone** to the 3rd of a minor tonic, where
major falls a semitone — the feedback derives the interval rather than assuming.

## When you don't know something

- **"No idea"** sits next to Check on every card. It reveals the answer without
  making you guess randomly first, and grades as Again.
- **"Explain this"** opens the relevant reference topic as a sheet over the
  session, so the queue survives. Eleven topics, also browsable from the Reference
  tab.

It is deliberately **not** reachable mid-attempt. Looking a card up before
answering turns a retrieval test into a reading exercise.

## Pricing

One price for the whole app — every deck, no in-app purchases, no subscription,
no entitlement code. Drills arrive in a four-stage didactic path that opens by
practice — and any stage can be opened by hand in Settings.

## Note spelling

Chords are built by diatonic interval arithmetic — letter distance plus exact
semitone distance — so D♭ and C♯ stay distinct and C°7 spells its seventh B♭♭.
The complete deck is snapshotted in `tests/unit/__golden__/`: `shells.txt`,
`chains.txt`, `rootless.txt`, `theory.txt` and `diatonic.txt`. Those were
reviewed by hand once; any diff is a spelling regression.

Grading is by sound, so the right key is always accepted — the spelling is shown
afterwards because reading it is a separate skill worth having.

## Building

```bash
npm install
npm run dev              # http://localhost:5173

npm run check            # svelte-check
npm run test:unit        # vitest — theory, grading, catalogue, gate, 630-day back-test
npm run test:e2e         # playwright — builds, serves statically, drives the real database
npm run icons            # regenerate assets/ and static/icon-*.png
npx capacitor-assets generate --ios --android \
  --iconBackgroundColor '#0f1117' --splashBackgroundColor '#0f1117'
```

### iOS

```bash
npm run ios:mirrors      # once — see below
npm run build && npx cap sync ios
cd ios/App && xcodebuild -project App.xcodeproj -scheme App \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

Two upstream defects stand between a fresh clone and a working iOS build. Both
are handled, but they are worth knowing about because neither reports itself.

**1. A dependency conflict that hangs instead of erroring.**
`@capacitor-community/sqlite` asks for `capacitor-swift-pm` by *branch* while
Capacitor's own generated manifest asks for it by *version*. SwiftPM cannot mix
the two for one package and, rather than saying so, hangs. `scripts/patch-capacitor-spm.mjs`
rewrites `branch:` to `from:` and runs from `postinstall`, so `npm install`
cannot reintroduce it.

**2. SwiftPM's binary-artifact downloader can hang forever.**
Capacitor 8 ships its iOS integration as prebuilt `.xcframework` zips. On some
machines SwiftPM prints `Downloading binary artifact …` and then sits at 0% CPU
indefinitely — no error, no timeout. It is not the network: `curl` and
`URLSession` both fetch the same URL in under a second, and a one-target test
package reproduces it. `npm run ios:mirrors` sidesteps it by vendoring the
frameworks into local git mirrors so there is nothing left to download.

If SwiftPM's downloader works on your machine you need neither: delete
`~/.spm-local-mirrors` and the two `mirrors.json` files and it resolves from
upstream normally.

### Android

Needs JDK 21 (Gradle 8.14 does not run on 26) and the Android SDK:

```bash
export JAVA_HOME="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
npm run build && npx cap sync android
cd android && ./gradlew assembleDebug
```

### Tests

- **Unit** — note spelling (golden files), grade derivation, mastery thresholds,
  catalogue stability and unambiguity, and the rootless gate driven against a
  real in-memory SQLite rather than a mock.
- **Back-test** — a synthetic learner run through 630 days of the real scheduler,
  asserting achieved retention lands within 3% of the request, that daily load
  settles instead of climbing, that nothing starves, and that an always-slow
  learner never reaches *automatic*. Honest limitation: the learner forgets
  according to FSRS's own curve, so the retention assertion tests configuration
  and interval arithmetic, not whether FSRS models human memory.
- **E2E** — every drill type, the path, the reference sheet, "No idea",
  export/import round-trip, running with the network cut, surviving a cold
  restart, and an axe-core pass over every screen and answer surface plus
  tap-target checks on an iPhone 14 Pro viewport.

E2E drives the app through `window.__voicings`, compiled in only when
`VITE_VT_TEST=1`. Store builds never define it, so the hook is dead code.

## The icon

A keyboard with two keys lit — the root and its guide tone, i.e. a shell
voicing, which is what the app is about. Five white keys rather than a full
octave: seven are indistinguishable at 40px.

`scripts/make-icons.mjs` draws it from source at 1024 and writes the PWA icons,
the store icon, an Android adaptive foreground/background pair, and the splash.
`capacitor-assets` then fans those out into every size iOS and Android want.

The adaptive foreground is drawn smaller than the store icon on purpose:
Android masks the outer third away, and artwork drawn to the edge comes back
with its corners bitten off.

## Your data

There is no server and no account, so the export is the only way practice
history leaves the phone — for a backup, or to move devices. Settings has export,
import and erase. `reviews` is append-only and everything else can be rebuilt
from it.

## Known limitations

- Grading happens on the device with no verification anywhere. For an app with no
  accounts and no leaderboards, there is nothing to cheat.
- Answers are pitch-class only, so octave placement is shown in the feedback but
  never marked wrong.
- Web MIDI is not supported by iOS Safari. The native shells could use CoreMIDI;
  they don't yet.
- Diatonic harmony and the modes drill cover major keys only.
- Progressions stop at ii–V–I in both modes. No turnarounds, no tritone subs.
- Playback is three synthesised partials, not a sampled piano: enough to hear a
  voicing, and small enough to ship with no binary assets.
