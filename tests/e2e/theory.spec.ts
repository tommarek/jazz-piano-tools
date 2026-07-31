import { expect, test } from '@playwright/test';
import { answerCurrent, currentCardId, expectedFor, reset, tapKeys } from './helpers';
import { CHORD_ROOTS } from '../../src/lib/music/voicings';
import { parseNote, pitchClass, prettyNoteName } from '../../src/lib/music/theory';

/**
 * A Web Audio stand-in stuck at 'suspended' — the state iOS hands back until a
 * user gesture unlocks the session. It accepts everything scheduled on it, so
 * playback succeeds; it just is not audible yet. Runs as an init script, so it
 * must be self-contained.
 */
function gateAudioBehindAGesture() {
	const param = () => ({
		value: 1,
		setValueAtTime() {},
		exponentialRampToValueAtTime() {},
		setTargetAtTime() {},
		cancelScheduledValues() {}
	});
	class GatedAudioContext {
		state = 'suspended';
		currentTime = 0;
		destination = { connect() {} };
		onstatechange: (() => void) | null = null;
		createGain() {
			return { gain: param(), connect() {} };
		}
		// The cutoff carries an envelope of its own — brightness dies before the
		// note does — so it is scheduled exactly like a gain.
		createBiquadFilter() {
			return { type: 'lowpass', frequency: param(), Q: { value: 0 }, connect() {} };
		}
		createPeriodicWave() {
			return {};
		}
		createOscillator() {
			return {
				type: 'sine',
				frequency: { value: 0 },
				detune: { value: 0 },
				onended: null,
				setPeriodicWave() {},
				connect() {},
				start() {},
				stop() {}
			};
		}
		// Never resolves: the gesture the app is waiting for is the Play tap the
		// test is about to make, and the context stays suspended either way.
		resume() {
			return new Promise<void>(() => {});
		}
	}
	Object.defineProperty(window, 'AudioContext', { value: GatedAudioContext });
	Object.defineProperty(window, 'webkitAudioContext', { value: GatedAudioContext });
}

test.describe('theory drills', () => {
	for (const [name, type] of [
		['chord tones & extensions', 'ext'],
		['intervals', 'ivl'],
		['diatonic harmony', 'dia'],
		['scales & modes', 'mode'],
		// gtc and rlc pre-light `given` keys, and rlc is an ordered answer — none
		// of that was driven anywhere until these were added, while the docs
		// claimed every drill type was covered.
		['guide tones', 'gt'],
		['guide tones → symbol', 'gtn'],
		['guide-tone comping', 'gtc'],
		['rootless comping', 'rlc']
	] as const) {
		test(`${name} can be answered right and wrong`, async ({ page }) => {
			await reset(page, { activeCardTypes: [type], newCardsPerDay: 4, sessionCardCap: 4 });
			await page.goto('/session');
			await expect(page.getByTestId('card-title')).toBeVisible();

			const card = expectedFor(await currentCardId(page));
			expect(card.type).toBe(type);

			await answerCurrent(page, false);
			await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'false');
			await expect(page.getByTestId('answer-text')).toHaveText(card.answerText);

			await page.getByTestId('next-card').click();
			await answerCurrent(page, true);
			await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'true');
		});
	}

	test('the intervals drill lights the root it is measuring from', async ({ page }) => {
		await reset(page, { activeCardTypes: ['ivl'], newCardsPerDay: 3 });
		await page.goto('/session');

		const card = expectedFor(await currentCardId(page));
		await expect(
			page.locator(`[data-testid="keyboard"] [data-pc="${card.rootGiven}"]`)
		).toHaveAttribute('data-state', 'given');
	});

	test('diatonic answers are accepted by pitch class, not by spelling', async ({ page }) => {
		// Thirteen of the 84 diatonic answers are spelled off the root grid — the
		// IV of G♭ is C♭, the vii of B is A♯. Tapping the enharmonic key must
		// count, and the feedback must still show the real spelling. The card's
		// root carries ♭/♯ glyphs and the picker's names are ASCII, so the two
		// alphabets have to be reconciled before anything is compared: a raw
		// includes() calls every accidental root off-grid and stops on D♭, which
		// is a correctly spelled grid root and proves nothing.
		await reset(page, { activeCardTypes: ['dia'], newCardsPerDay: 50, sessionCardCap: 50 });
		await page.goto('/session');
		await expect(page.getByTestId('card-title')).toBeVisible();

		let found = false;
		for (let i = 0; i < 50 && !found; i++) {
			if (!(await page.getByTestId('card-title').isVisible())) break;
			const card = expectedFor(await currentCardId(page));
			const chord = card.expectedChord!;
			const offGrid = !CHORD_ROOTS.some((r) => prettyNoteName(r) === chord.root);

			if (offGrid) {
				const enharmonic = CHORD_ROOTS.find(
					(r) => pitchClass(parseNote(r, 4)) === chord.rootPc
				)!;
				expect(prettyNoteName(enharmonic)).not.toBe(chord.root);
				await page.getByTestId(`root-${enharmonic}`).click();
				await page.getByTestId(`quality-${chord.quality}`).click();
				await page.getByTestId('check-answer').click();
				await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'true');
				await expect(page.getByTestId('answer-text')).toHaveText(card.answerText);
				expect(card.answerText.startsWith(chord.root)).toBe(true);
				found = true;
			} else {
				await answerCurrent(page, true);
			}
			await page.getByTestId('next-card').click();
		}
		expect(found, 'no off-grid diatonic answer appeared').toBe(true);
	});
});

test.describe('ear training', () => {
	for (const [name, type] of [
		['intervals by ear', 'eint'],
		['chord quality by ear', 'eqal']
	] as const) {
		test(`${name} answers from the sound alone`, async ({ page }) => {
			await reset(page, { activeCardTypes: [type], newCardsPerDay: 4, sessionCardCap: 4 });
			await page.goto('/session?deck=ear');
			await expect(page.getByTestId('card-title')).toBeVisible();

			const card = expectedFor(await currentCardId(page));
			expect(card.type).toBe(type);

			// The prompt is the play button, and nothing else: a keyboard showing
			// the notes would hand over the answer.
			await expect(page.getByTestId('play-prompt')).toBeVisible();
			await expect(page.getByTestId('keyboard')).toHaveCount(0);
			// Replaying before answering is part of the drill, not a way round it,
			// and the button says which of the two it is doing — so asserting that
			// is what tells a working replay from a dead tap.
			await page.getByTestId('play-prompt').click();
			await expect(page.getByTestId('play-prompt')).toContainText('Play it again');
			await expect(page.getByTestId('prompt-hint')).toContainText('as often as you like');

			await answerCurrent(page, false);
			await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'false');
			// Named and spelled on reveal — there is nothing left to give away.
			await expect(page.getByTestId('answer-text')).toHaveText(card.answerText);

			await page.getByTestId('next-card').click();
			await answerCurrent(page, true);
			await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'true');
		});
	}

	test('carry the prompt on the play button when autoplay is refused', async ({ page }) => {
		// iOS only unlocks audio inside a user gesture, so a session opening on an
		// ear card cannot sound it. The button becomes the prompt — and the wait
		// for that tap is not thinking time, so the clock restarts when it lands.
		//
		// A context parked at 'suspended' is that browser: it accepts everything
		// scheduled on it and speaks the moment the gesture lands. This used to be
		// tested by deleting Web Audio outright, which is the other case entirely
		// — nothing ever sounds — and is the test below.
		await page.addInitScript(gateAudioBehindAGesture);
		await reset(page, { activeCardTypes: ['eint'], newCardsPerDay: 4, sessionCardCap: 4 });
		await page.goto('/session?deck=ear');
		await expect(page.getByTestId('card-title')).toBeVisible();

		// Nothing has sounded, and the card says so rather than reading as dead.
		await expect(page.getByTestId('play-prompt')).toContainText('Play');
		await expect(page.getByTestId('play-prompt')).not.toContainText('again');
		await expect(page.getByTestId('prompt-hint')).toContainText('Tap to hear it');

		await page.waitForTimeout(1500);
		await page.getByTestId('play-prompt').click();
		await expect(page.getByTestId('play-prompt')).toContainText('Play it again');

		await page.getByTestId('give-up').click();
		// The 1.5 seconds spent waiting for a prompt that had not played must not
		// be in the response time; only what came after the tap counts.
		const feedback = await page.getByTestId('feedback').textContent();
		const seconds = Number(/(\d+\.\d)s/.exec(feedback ?? '')?.[1]);
		expect(seconds).toBeLessThan(1);
	});

	test('own up when the device has no sound at all, rather than faking a replay', async ({
		page
	}) => {
		// An ear card has no prompt but its sound. If playback silently fails and
		// the button still flips to "Play it again", the learner is left with a
		// card that insists it asked a question they never heard and no way out of
		// it. Deleting Web Audio is the real thing, not a stand-in: old WebViews
		// genuinely ship without it.
		await page.addInitScript(() => {
			Object.defineProperty(window, 'AudioContext', { value: undefined });
			Object.defineProperty(window, 'webkitAudioContext', { value: undefined });
		});
		await reset(page, { activeCardTypes: ['eint'], newCardsPerDay: 4, sessionCardCap: 4 });
		await page.goto('/session?deck=ear');
		await expect(page.getByTestId('card-title')).toBeVisible();

		await page.getByTestId('play-prompt').click();
		await expect(page.getByTestId('play-prompt')).not.toContainText('again');
		await expect(page.getByTestId('play-prompt')).toContainText('No sound');
		// Both ways out are named: the escape hatch for this card, and the setting
		// that takes the ear drills out of the deck for good.
		const hint = page.getByTestId('prompt-hint');
		await expect(hint).toContainText('No idea');
		await expect(hint).toContainText('Settings');

		// And the named escape hatch actually works.
		await page.getByTestId('give-up').click();
		await expect(page.getByTestId('feedback')).toBeVisible();
	});

	test('do not claim you played an interval after "No idea"', async ({ page }) => {
		// The graded picker keeps the chosen and the correct button. With nothing
		// chosen there is one button left, and captioning it "You played" would
		// tell the learner they played something they never touched.
		await reset(page, { activeCardTypes: ['eint'], newCardsPerDay: 4, sessionCardCap: 4 });
		await page.goto('/session?deck=ear');
		await expect(page.getByTestId('card-title')).toBeVisible();

		await page.getByTestId('give-up').click();
		await expect(page.getByTestId('feedback')).toBeVisible();
		await expect(page.getByText('It was', { exact: true })).toBeVisible();
		await expect(page.getByText('You played · it was')).toHaveCount(0);
	});

	test('the ear drills leave the deck when sound is off', async ({ page }) => {
		// With playback off they would come up with no question on screen at all.
		await reset(page, {
			activeCardTypes: ['eint', 'eqal'],
			soundEnabled: false,
			newCardsPerDay: 8
		});
		await page.goto('/session?deck=ear');
		await expect(page.getByTestId('session-summary')).toBeVisible();
		// And says which switch emptied it: "nothing due" would send the learner
		// away for the day over a setting they can flip now.
		await expect(page.getByTestId('empty-reason')).toContainText('Play the answer');
		await expect(page.getByTestId('empty-reason')).not.toContainText('Nothing due');

		// Out of an ear session is back to Ear, never across to Theory.
		await page.getByRole('link', { name: 'Done' }).click();
		await expect(page).toHaveURL(/\/ear$/);
	});
});

test.describe('minor ii–V–i', () => {
	test('is a distinct card from the major chain in the same key', async ({ page }) => {
		await reset(page, { activeCardTypes: ['chain'], newCardsPerDay: 48, sessionCardCap: 48 });
		await page.goto('/session');

		const seen = new Set<string>();
		for (let i = 0; i < 12; i++) {
			seen.add(await currentCardId(page));
			await answerCurrent(page, true);
			await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'true');
			await page.getByTestId('next-card').click();
		}
		expect([...seen].some((id) => id.endsWith(':minor'))).toBe(true);
		expect([...seen].some((id) => !id.endsWith(':minor'))).toBe(true);
	});
});

test.describe('rootless voicings', () => {
	test('stay out of the deck until they are unlocked', async ({ page }) => {
		await reset(page, {
			activeCardTypes: ['rootless'],
			newCardsPerDay: 10,
			unlockedStages: 1
		});
		await page.goto('/');
		await expect(page.getByTestId('gate-progress')).toBeVisible();
		await expect(page.getByTestId('due-count')).toHaveText('0');
	});

	test('can be added by hand, and then require the right order', async ({ page }) => {
		await reset(page, {
			activeCardTypes: ['rootless'],
			newCardsPerDay: 10,
			unlockedStages: 3
		});
		await page.goto('/session');

		const card = expectedFor(await currentCardId(page));
		expect(card.type).toBe('rootless');
		const step = card.steps[0];
		expect(step.ordered).toBe(true);
		expect(step.expected).toHaveLength(4);

		// The same four notes in the wrong order is the other form, so it is wrong.
		const reversed = [...step.expected].reverse();
		await tapKeys(page, reversed);
		await page.getByTestId('check-answer').click();
		await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'false');
		await page.getByTestId('next-card').click();

		// And bottom-up is right.
		const next = expectedFor(await currentCardId(page));
		await tapKeys(page, next.steps[0].expected);
		await expect(page.locator('[data-testid="keyboard"] [data-order="4"]')).toBeVisible();
		await page.getByTestId('check-answer').click();
		await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'true');
	});

	test('says so when only the order was wrong, and shows the right one', async ({ page }) => {
		await reset(page, {
			activeCardTypes: ['rootless'],
			newCardsPerDay: 10,
			unlockedStages: 3
		});
		await page.goto('/session');

		const card = expectedFor(await currentCardId(page));
		const expectedOrder = card.steps[0].expected;
		await tapKeys(page, [...expectedOrder].reverse());
		await page.getByTestId('check-answer').click();

		await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'false');
		// Every note goes green on reveal, so without this the screen reads as a pass.
		await expect(page.getByTestId('order-miss')).toBeVisible();

		// The badges must now teach the correct sequence, not repeat the mistake.
		for (let i = 0; i < expectedOrder.length; i++) {
			await expect(
				page.locator(`[data-testid="keyboard"] [data-pc="${expectedOrder[i]}"] [data-order]`)
			).toHaveAttribute('data-order', String(i + 1));
		}
	});

	test('does not claim an order miss when the notes were also wrong', async ({ page }) => {
		await reset(page, {
			activeCardTypes: ['rootless'],
			newCardsPerDay: 10,
			unlockedStages: 3
		});
		await page.goto('/session');

		const card = expectedFor(await currentCardId(page));
		await tapKeys(page, card.steps[0].expected.map((pc) => (pc + 1) % 12));
		await page.getByTestId('check-answer').click();

		await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'false');
		await expect(page.getByTestId('order-miss')).toHaveCount(0);
	});
});

test.describe('a phone screen', () => {
	/**
	 * Regression: the reveal panel, the movement graph and the keyboard together
	 * ran 130px past a 390×664 phone, and because the Next bar is sticky and
	 * opaque the bottom of the keyboard — the order badges included — sat behind
	 * it however far you scrolled. The drills with the tallest reveals are
	 * checked: the three that draw the graph, plus dia, which draws none — its
	 * sound is one group — but stacks a root grid, a quality row and a rationale.
	 * gtn is here for the answer phase rather than the reveal: it is the one
	 * drill that shows a keyboard and a picker at once, and at full key height
	 * the bottom quality buttons sat under the bar on anything under 390dp.
	 */
	for (const type of ['chain', 'gtc', 'rlc', 'dia', 'gtn'] as const) {
		test(`fits ${type} in both phases`, async ({ page }) => {
			await reset(page, { activeCardTypes: [type], newCardsPerDay: 4, unlockedStages: 3 });
			await page.setViewportSize({ width: 390, height: 664 });
			await page.goto(`/session?deck=${type}`);
			await expect(page.locator('[data-card-id]')).toBeVisible();

			const overflow = async () =>
				page.evaluate(() => document.documentElement.scrollHeight - window.innerHeight);
			expect(await overflow(), 'answer phase').toBeLessThanOrEqual(0);

			await answerCurrent(page, false);
			await expect(page.getByTestId('feedback')).toBeVisible();
			expect(await overflow(), 'reveal').toBeLessThanOrEqual(0);
			await expect(page.getByTestId('next-card')).toBeInViewport();

			// The bar is opaque, so "on the page" is not enough: the reveal has to
			// clear it. Nothing is being taught by a key hidden under a button.
			const clear = await page.evaluate(() => {
				const kb = document.querySelector('[data-testid="keyboard"]');
				const bar = document.querySelector('[data-testid="next-card"]')!.parentElement!;
				return kb ? bar.getBoundingClientRect().top - kb.getBoundingClientRect().bottom : 1;
			});
			expect(clear).toBeGreaterThanOrEqual(0);
		});
	}

	/**
	 * Regression: the session sized itself against a hard-coded 2rem of chrome
	 * while <main> pads by the top safe-area inset, so on a notched phone it
	 * stood a notch taller than the screen and the opaque bar sat over the bottom
	 * of the keyboard however far you scrolled. Playwright reports every inset as
	 * zero, so the notch is simulated by setting the pad both places read.
	 *
	 * On a viewport with room to spare, deliberately: what is under test is the
	 * arithmetic of the session's own min-height, not how much a card needs —
	 * that is the 390×664 budget above, and no notched phone is that short.
	 */
	test('sizes itself to the screen the notch leaves', async ({ page }) => {
		await reset(page, { activeCardTypes: ['chain'], newCardsPerDay: 4, unlockedStages: 3 });
		await page.setViewportSize({ width: 390, height: 900 });
		await page.goto('/session?deck=chain');
		await expect(page.locator('[data-card-id]')).toBeVisible();
		await page.evaluate(() => document.documentElement.style.setProperty('--pad-top', '59px'));

		const overflow = async () =>
			page.evaluate(() => document.documentElement.scrollHeight - window.innerHeight);
		expect(await overflow(), 'answer phase').toBeLessThanOrEqual(0);

		await answerCurrent(page, false);
		await expect(page.getByTestId('feedback')).toBeVisible();
		expect(await overflow(), 'reveal').toBeLessThanOrEqual(0);

		// The bar is opaque and sticky, so the session ending below the fold means
		// the bottom of the keyboard is behind it, unreachably.
		const clear = await page.evaluate(() => {
			const kb = document.querySelector('[data-testid="keyboard"]')!;
			const bar = document.querySelector('[data-testid="next-card"]')!.parentElement!;
			return bar.getBoundingClientRect().top - kb.getBoundingClientRect().bottom;
		});
		expect(clear).toBeGreaterThanOrEqual(0);
	});

	/**
	 * Regression, at the narrower phone the answer phase has to survive: gtn is
	 * the only drill showing a keyboard and a picker at once, and at full key
	 * height the bottom row of quality buttons sat behind the opaque Check bar
	 * on a 375dp screen — the one row you cannot answer the card without.
	 */
	test('fits gtn while it is being answered on a 375dp phone', async ({ page }) => {
		await reset(page, { activeCardTypes: ['gtn'], newCardsPerDay: 4, unlockedStages: 3 });
		await page.setViewportSize({ width: 375, height: 667 });
		await page.goto('/session?deck=gtn');
		await expect(page.locator('[data-card-id]')).toBeVisible();

		const overflow = await page.evaluate(
			() => document.documentElement.scrollHeight - window.innerHeight
		);
		expect(overflow).toBeLessThanOrEqual(0);

		const clear = await page.evaluate(() => {
			const picker = [...document.querySelectorAll('[data-testid^="quality-"]')].map(
				(el) => el.getBoundingClientRect().bottom
			);
			const bar = document.querySelector('[data-testid="check-answer"]')!.parentElement!;
			return bar.getBoundingClientRect().top - Math.max(...picker);
		});
		expect(clear).toBeGreaterThanOrEqual(0);
	});
});

test.describe('ear cards on a phone screen', () => {
	// Regression: the reveal panel plus an eleven-button picker pushed the
	// answer below the fold, so the one thing feedback exists to show was the
	// one thing you had to scroll for.
	test('fit the viewport in both phases', async ({ page }) => {
		await reset(page, { activeCardTypes: ['eint'], newCardsPerDay: 5 });
		await page.setViewportSize({ width: 390, height: 664 });
		await page.goto('/session?deck=ear');
		await expect(page.getByTestId('card-title')).toBeVisible();

		const overflow = async () =>
			page.evaluate(() => document.documentElement.scrollHeight - window.innerHeight);
		expect(await overflow()).toBeLessThanOrEqual(0);

		await answerCurrent(page, false);
		await expect(page.getByTestId('feedback')).toBeVisible();
		expect(await overflow()).toBeLessThanOrEqual(0);
		// The graded picker must still be on screen, not scrolled away.
		await expect(page.getByTestId('next-card')).toBeInViewport();
	});
});
