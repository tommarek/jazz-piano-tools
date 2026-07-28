import type { Page } from '@playwright/test';
import { parseCardId, renderCard } from '../../src/lib/music/cards';
import { CHORD_ROOTS, QUALITIES } from '../../src/lib/music/voicings';
import { DRILLED_INTERVALS, MODE_NAMES } from '../../src/lib/music/theory-drills';
import { parseNote, pitchClass } from '../../src/lib/music/theory';
import type { Settings } from '../../src/lib/data/settings';

/**
 * Answers are derived from the card id using the same engine the app uses.
 * That is deliberate: the correctness of the notes is locked down by the golden
 * file, so the E2E suite is free to assume it and test the flow instead.
 */
export function expectedFor(cardId: string) {
	const spec = parseCardId(cardId);
	if (!spec) throw new Error(`Not a card id: ${cardId}`);
	return renderCard(spec);
}

/**
 * Resets the on-device database through the test hook the build exposes.
 * Navigates first, because the hook only exists once the app has booted.
 */
export async function reset(page: Page, settings: Partial<Settings> = {}) {
	await page.goto('/');
	await page.waitForFunction(() => '__voicings' in window, null, { timeout: 20_000 });
	await page.evaluate(
		async ([s]) => {
			await (
				window as unknown as { __voicings: { reset(s: unknown): Promise<void> } }
			).__voicings.reset(s);
		},
		[settings] as const
	);
}

export async function currentCardId(page: Page): Promise<string> {
	// The queue is built from the on-device database after navigation, so the
	// first card lands a tick late — every caller would otherwise have to
	// remember to wait for it.
	const el = page.locator('[data-card-id]');
	await el.waitFor({ timeout: 20_000 });
	const id = await el.getAttribute('data-card-id');
	if (!id) throw new Error('No card on screen');
	return id;
}

/** Taps the given pitch classes on the on-screen keyboard. */
export async function tapKeys(page: Page, pitchClasses: number[]) {
	for (const pc of pitchClasses) {
		await page.locator(`[data-testid="keyboard"] [data-pc="${pc}"]`).click();
	}
}

/** Answers the card currently on screen, correctly or deliberately wrongly. */
export async function answerCurrent(page: Page, correct = true) {
	const id = await currentCardId(page);
	const card = expectedFor(id);

	if (card.input === 'shell-name') {
		const shell = card.expectedShell!;
		const root = correct ? shell.root : shell.root === 'C' ? 'D' : 'C';
		await page.getByTestId(`root-${root}`).click();
		await page.getByTestId(`guide-${shell.guide}`).click();
	} else if (card.input === 'quality-name') {
		// Quality only — the root is marked on the prompt keyboard. A wrong
		// answer picks a quality outside the accepted set.
		const accepted = card.expectedChord!.alsoAccept ?? [card.expectedChord!.quality];
		const wrongQ = QUALITIES.find(
			(q) => !accepted.includes(q as (typeof accepted)[number])
		)!;
		await page.getByTestId(`quality-${correct ? card.expectedChord!.quality : wrongQ}`).click();
	} else if (card.input === 'chord-name') {
		const chord = card.expectedChord!;
		// Graded on pitch class, so pick whichever grid root sounds the same.
		const onGrid =
			CHORD_ROOTS.find((r) => pitchClass(parseNote(r, 4)) === chord.rootPc) ?? 'C';
		const root = correct ? onGrid : onGrid === 'C' ? 'D' : 'C';
		const quality = correct ? chord.quality : chord.quality === 'm7' ? 'maj7' : 'm7';
		await page.getByTestId(`root-${root}`).click();
		await page.getByTestId(`quality-${quality}`).click();
	} else if (card.input === 'mode-name') {
		const wrong = MODE_NAMES.find((m) => m !== card.expectedMode)!;
		await page.getByTestId(`mode-${correct ? card.expectedMode : wrong}`).click();
	} else if (card.input === 'interval-name') {
		const wrong = DRILLED_INTERVALS.find((i) => i !== card.expectedInterval)!;
		await page.getByTestId(`interval-${correct ? card.expectedInterval : wrong}`).click();
	} else {
		for (let i = 0; i < card.steps.length; i++) {
			const step = card.steps[i];
			// Chain cards auto-advance, but clicking the chip is idempotent and
			// makes the intent explicit when a step is revisited.
			if (card.steps.length > 1) await page.getByTestId(`step-${i}`).click();
			const answer = correct
				? step.expected
				: step.expected.map((pc) => (pc + 1) % 12);
			await tapKeys(page, answer);
		}
	}

	await page.getByTestId('check-answer').click();
	// Wait for the write to land, not just for the feedback to render.
	await page.locator('[data-testid="feedback"][data-saved="true"]').waitFor({ timeout: 10_000 });
	return card;
}
