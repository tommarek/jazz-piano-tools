import { expect, test } from '@playwright/test';
import { answerCurrent, currentCardId, expectedFor, reset, tapKeys } from './helpers';

test.describe('the critical path', () => {
	test.beforeEach(async ({ page }) => {
		// A narrow deck keeps the queue predictable without weakening the flow test.
		await reset(page, {
			activeCardTypes: ['gt'],
			activeQualities: ['maj7', 'm7'],
			newCardsPerDay: 10,
			sessionCardCap: 10
		});
	});

	test('start a session, answer five cards, see the summary and updated stats', async ({
		page
	}) => {
		await page.goto('/');
		await expect(page.getByTestId('due-count')).toHaveText('10');
		await expect(page.getByTestId('today-count')).toHaveText('0');

		await page.getByTestId('start-session').click();
		await expect(page.getByTestId('card-title')).toBeVisible();

		for (let i = 0; i < 5; i++) {
			await answerCurrent(page, true);
			await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'true');
			await page.getByTestId('next-card').click();
		}

		await page.getByTestId('end-session').click();
		await expect(page.getByTestId('session-summary')).toBeVisible();
		await expect(page.getByTestId('summary-answered')).toHaveText('5');

		await page.goto('/');
		await expect(page.getByTestId('today-count')).toHaveText('5');
		await expect(page.getByTestId('due-count')).toHaveText('5');
	});

	test('a wrong answer reveals the right one and comes back in the same session', async ({
		page
	}) => {
		await page.goto('/session');
		const firstId = await currentCardId(page);
		const card = expectedFor(firstId);

		// The first card of a fresh deck is introduced here, badge and all.
		await expect(page.getByTestId('card-eyebrow')).toContainText('new');

		await answerCurrent(page, false);
		const feedback = page.getByTestId('feedback');
		await expect(feedback).toHaveAttribute('data-correct', 'false');
		await expect(page.getByTestId('answer-text')).toHaveText(card.answerText);
		await expect(feedback).toContainText("You'll see this one again");

		// It must reappear before the session ends — and not as a new card: by
		// then it has been introduced, answered and written to card_state.
		const seen: string[] = [];
		for (let i = 0; i < 8; i++) {
			await page.getByTestId('next-card').click();
			if (!(await page.getByTestId('card-title').isVisible())) break;
			const id = await currentCardId(page);
			seen.push(id);
			if (id === firstId) {
				await expect(page.getByTestId('card-eyebrow')).not.toContainText('new');
			}
			await answerCurrent(page, true);
		}
		expect(seen).toContain(firstId);
	});

	test('promises the repeat on a miss near the end of a short queue', async ({ page }) => {
		// Five cards, missed on the fourth: the copy cannot go REQUEUE_GAP ahead,
		// so it is clamped to the end of the queue — still inside the session, and
		// the reveal used to say the opposite.
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 5, sessionCardCap: 50 });
		await page.goto('/session');
		for (let i = 0; i < 3; i++) {
			await answerCurrent(page, true);
			await page.getByTestId('next-card').click();
		}
		const missedId = await currentCardId(page);
		await answerCurrent(page, false);
		await expect(page.getByTestId('feedback')).toContainText(
			"You'll see this one again before the session ends"
		);

		const seen: string[] = [];
		for (let i = 0; i < 3; i++) {
			await page.getByTestId('next-card').click();
			if (!(await page.getByTestId('card-title').isVisible())) break;
			seen.push(await currentCardId(page));
			await answerCurrent(page, true);
		}
		expect(seen).toContain(missedId);
	});

	test('the progress bar does not walk backwards on a miss', async ({ page }) => {
		// A miss requeues its card, so the queue grows under the learner: read
		// live, the bar shrank at exactly the moment the miss feedback appeared.
		await page.goto('/session');
		const bar = page.getByTestId('session-progress');
		for (let i = 0; i < 3; i++) {
			await answerCurrent(page, true);
			await page.getByTestId('next-card').click();
		}
		const before = await bar.getAttribute('style');
		await answerCurrent(page, false);
		await expect(page.getByTestId('feedback')).toBeVisible();
		expect(await bar.getAttribute('style')).toBe(before);
	});

	test('a double-tap on Check does not skip the reveal it asked for', async ({ page }) => {
		await page.goto('/session');
		const id = await currentCardId(page);
		const card = expectedFor(id);
		await tapKeys(page, card.steps[0].expected);

		// Both taps land on the same spot: Next renders exactly where Check was.
		await page.getByTestId('check-answer').dblclick();
		await expect(page.getByTestId('feedback')).toBeVisible();
		expect(await currentCardId(page)).toBe(id);

		// And it advances the moment it is armed, so nothing is stuck.
		await page.getByTestId('next-card').click();
		expect(await currentCardId(page)).not.toBe(id);
	});
});

test.describe('empty sessions', () => {
	test('a speed round with nothing mastered explains itself', async ({ page }) => {
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 5 });
		await page.goto('/session?mode=speed');

		await expect(page.getByTestId('session-summary')).toBeVisible();
		// Pointing at newCardsPerDay here would be sending you to the wrong knob.
		await expect(page.getByTestId('empty-reason')).toContainText('already automatic');
		await expect(page.getByTestId('empty-reason')).not.toContainText('Nothing was due');
		// No cards answered is not 0% correct.
		await expect(page.getByTestId('summary-answered')).toHaveText('0');
		await expect(page.getByText('—').first()).toBeVisible();
	});

	test('a normal session with nothing due points at the right setting', async ({ page }) => {
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 0 });
		await page.goto('/session');
		await expect(page.getByTestId('empty-reason')).toContainText('new cards per day');
	});
});

test.describe('chain cards', () => {
	test.beforeEach(async ({ page }) => {
		await reset(page, { activeCardTypes: ['chain'], newCardsPerDay: 5, sessionCardCap: 5 });
	});

	test('require all three chords before they can be checked', async ({ page }) => {
		await page.goto('/session');
		const card = expectedFor(await currentCardId(page));
		expect(card.steps).toHaveLength(3);

		const check = page.getByTestId('check-answer');
		await expect(check).toBeDisabled();

		// One chord in: still not answerable.
		await tapKeys(page, card.steps[0].expected);
		await expect(check).toBeDisabled();
		await expect(page.getByTestId('step-0')).toHaveAttribute('data-filled', 'true');

		// Two chords in: still not answerable.
		await tapKeys(page, card.steps[1].expected);
		await expect(check).toBeDisabled();

		await tapKeys(page, card.steps[2].expected);
		await expect(check).toBeEnabled();
		await check.click();
		await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'true');
	});

	test('let a filled chord be corrected without jumping to the next one', async ({ page }) => {
		// Auto-advance used to fire on any tap that left a step full, so going
		// back to fix the ii moved the cursor to the V after one tap: the next
		// tap edited a chord the learner thought they had left alone, and the
		// chain graded wrong on a step they believed they had just repaired.
		await page.goto('/session');
		const card = expectedFor(await currentCardId(page));
		for (const step of card.steps) await tapKeys(page, step.expected);

		await page.getByTestId('step-0').click();
		await expect(page.getByTestId('step-0')).toHaveClass(/border-brass/);
		// Clear one note and replace it: still on the ii afterwards.
		await tapKeys(page, [card.steps[0].expected[0]]);
		await tapKeys(page, [card.steps[0].expected[0]]);
		await expect(page.getByTestId('step-0')).toHaveClass(/border-brass/);
		await expect(page.getByTestId('step-1')).not.toHaveClass(/border-brass/);

		await page.getByTestId('check-answer').click();
		await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'true');
	});
});

test.describe('visualise-then-place', () => {
	test('hides the keyboard for the whole delay', async ({ page }) => {
		await reset(page, {
			activeCardTypes: ['gt'],
			visualiseDelayMs: 2000,
			newCardsPerDay: 3
		});
		await page.goto('/session');

		const keyboard = page.getByTestId('keyboard');
		await expect(keyboard).toHaveAttribute('data-blanked', 'true');
		// Genuinely gone, not merely transparent.
		await expect(page.locator('[data-testid="keyboard"] [data-pc]')).toHaveCount(0);
		await expect(page.getByTestId('check-answer')).toBeDisabled();

		await expect(keyboard).toHaveAttribute('data-blanked', 'false', { timeout: 4000 });
		await expect(page.locator('[data-testid="keyboard"] [data-pc="0"]')).toBeVisible();
	});
});

test.describe('notes to symbol', () => {
	test('accepts any quality the guide-tone pair fits', async ({ page }) => {
		await reset(page, { activeCardTypes: ['gtn'], newCardsPerDay: 3 });
		await page.goto('/session');
		await expect(page.getByTestId('card-title')).toBeVisible();

		const card = expectedFor(await currentCardId(page));
		const accepted = card.expectedChord!.alsoAccept ?? [card.expectedChord!.quality];
		// Any reading in the class counts — the pair fixes neither quality nor root.
		await page.getByTestId(`quality-${accepted[accepted.length - 1]}`).click();
		await page.getByTestId('check-answer').click();
		await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'true');
	});

	test('lights the pair rather than spelling it out', async ({ page }) => {
		await reset(page, { activeCardTypes: ['gtn'], newCardsPerDay: 3 });
		await page.goto('/session');

		const card = expectedFor(await currentCardId(page));
		expect(card.given).toHaveLength(2);
		// The prompt lights the notes rather than spelling them out — printing
		// "Db – Fb" would hand over the answer.
		for (const pc of card.given) {
			await expect(
				page.locator(`[data-testid="keyboard"] [data-pc="${pc}"]`)
			).toHaveAttribute('data-state', 'given');
		}
		await expect(page.getByTestId('card-title')).not.toContainText(card.expectedChord!.root);

		await answerCurrent(page, true);
		await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'true');
	});
});

/**
 * Decks. The mixed session is still the default and still one tap; a deck is
 * the escape hatch for a weakness you already know about. What has to hold is
 * that picking one actually narrows the session, and that the path's gates
 * survive a deck being named in a URL.
 */
test.describe('drilling one deck', () => {
	test('a drill deck deals that drill and nothing else', async ({ page }) => {
		await reset(page, { unlockedStages: 3, newCardsPerDay: 12, sessionCardCap: 12 });
		await page.goto('/');

		// The stage row expands to the drills inside it.
		await page.getByTestId('expand-stage-1').click();
		await page.getByTestId('deck-ivl').click();

		await expect(page.getByTestId('session-deck')).toHaveText('Intervals');
		for (let i = 0; i < 4; i++) {
			expect(await currentCardId(page)).toMatch(/^ivl:/);
			await answerCurrent(page, true);
			await page.getByTestId('next-card').click();
		}
	});

	test('a stage deck interleaves the drills inside it', async ({ page }) => {
		await reset(page, { unlockedStages: 3, newCardsPerDay: 12, sessionCardCap: 12 });
		await page.goto('/');
		await page.getByTestId('deck-stage-1').click();

		await expect(page.getByTestId('session-deck')).toHaveText('Guide tones');
		const seen = new Set<string>();
		for (let i = 0; i < 6; i++) {
			const id = await currentCardId(page);
			seen.add(id.split(':')[0]);
			// Every card belongs to stage 1, whichever of its drills it came from.
			expect(['gt', 'gtn', 'ivl']).toContain(id.split(':')[0]);
			await answerCurrent(page, true);
			await page.getByTestId('next-card').click();
		}
		// A stage is several drills, so a stage session is still mixed practice.
		expect(seen.size).toBeGreaterThan(1);
	});

	test('the mixed session is untouched and still the default', async ({ page }) => {
		await reset(page, { unlockedStages: 3, newCardsPerDay: 12, sessionCardCap: 12 });
		await page.goto('/');
		await page.getByTestId('start-session').click();
		// No deck label: this is the everything queue.
		await expect(page.getByTestId('session-deck')).toHaveCount(0);
		await expect(page.getByTestId('card-title')).toBeVisible();
	});

	test('a stage ahead of the path can be drilled, and says that it is ahead', async ({ page }) => {
		await reset(page, { unlockedStages: 1, newCardsPerDay: 12 });
		await page.goto('/');
		// Tappable: the path suggests an order, it does not forbid one.
		await expect(page.getByTestId('deck-picker')).toContainText('ahead');
		await page.getByTestId('deck-stage-3').click();

		await expect(page.getByTestId('session-deck')).toHaveText('Rootless & colours');
		expect(await currentCardId(page)).toMatch(/^(rootless|rlc|ext|mode):/);
	});

	test('but the mixed session still respects the path', async ({ page }) => {
		await reset(page, { unlockedStages: 1, newCardsPerDay: 12, sessionCardCap: 12 });
		await page.goto('/');
		await page.getByTestId('start-session').click();
		for (let i = 0; i < 5; i++) {
			expect(await currentCardId(page)).toMatch(/^(gt|gtn|ivl):/);
			await answerCurrent(page, true);
			await page.getByTestId('next-card').click();
		}
	});
});

/**
 * The progression cards: where the hand is, and how little it moves.
 */
test.describe('voice leading on progression cards', () => {
	test('the previous chord stays on the keyboard while entering the next', async ({ page }) => {
		await reset(page, { activeCardTypes: ['chain'], unlockedStages: 2, newCardsPerDay: 4 });
		await page.goto('/session');
		const card = expectedFor(await currentCardId(page));

		await tapKeys(page, card.steps[0].expected);
		// Auto-advanced to the V; the ii's keys are marked as where the hand is,
		// because the next chord is played FROM them — one holds, one steps.
		await expect(page.getByTestId('step-1')).toHaveAttribute('class', /border-brass/);
		for (const pc of card.steps[0].expected) {
			await expect(
				page.locator(`[data-testid="keyboard"] [data-pc="${pc}"]`)
			).toHaveAttribute('data-prev', 'true');
		}
	});

	test('the reveal draws the movement, and the small moves get named', async ({ page }) => {
		await reset(page, { activeCardTypes: ['chain'], unlockedStages: 2, newCardsPerDay: 4 });
		await page.goto('/session');
		await answerCurrent(page, true);

		const graph = page.getByTestId('voice-leading');
		await expect(graph).toBeVisible();
		// Every chain holds or steps its guide tone; the labels are the point.
		await expect(graph).toContainText(/held|½|1/);
	});

	test('a transition card draws its two chords too', async ({ page }) => {
		await reset(page, { activeCardTypes: ['gtc'], unlockedStages: 2, newCardsPerDay: 4 });
		await page.goto('/session');
		await answerCurrent(page, true);
		await expect(page.getByTestId('voice-leading')).toBeVisible();
	});

	test('a single voicing has no movement to draw', async ({ page }) => {
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 4 });
		await page.goto('/session');
		await answerCurrent(page, true);
		await expect(page.getByTestId('voice-leading')).toHaveCount(0);
	});
});

/**
 * Switching decks. The nav is hidden while drilling — deliberately, the screen
 * is tight and a session should not invite wandering — so the end of one is
 * where "what next" gets asked.
 */
test.describe('changing deck', () => {
	test('the summary offers the section’s other decks, and they start', async ({ page }) => {
		await reset(page, { unlockedStages: 3, newCardsPerDay: 6, sessionCardCap: 6 });
		await page.goto('/session?deck=stage-1');
		await page.getByTestId('end-session').click();

		const switcher = page.getByTestId('deck-switcher');
		await expect(switcher).toBeVisible();
		// Not the deck just drilled: offering it as "another deck" is the one
		// useless row.
		await expect(page.getByTestId('switch-stage-1')).toHaveCount(0);

		await page.getByTestId('switch-stage-2').click();
		await expect(page.getByTestId('session-deck')).toHaveText('The ii–V–I');
		expect(await currentCardId(page)).toMatch(/^(chain|gtc|dia):/);
	});

	test('and counts them again at the end, not from the pre-session snapshot', async ({ page }) => {
		// The loader's counts were taken before a card was answered. Reusing them
		// on the summary offered a deck this very session had just emptied — the
		// row that starts an empty session, which the filter exists to remove.
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 3, sessionCardCap: 3 });
		await page.goto('/session');
		for (let i = 0; i < 3; i++) {
			await answerCurrent(page, true);
			await page.getByTestId('next-card').click();
		}

		await expect(page.getByTestId('session-summary')).toBeVisible();
		await expect(page.getByTestId('switch-stage-1')).toHaveCount(0);
	});

	test('an ear session offers ear decks, never theory ones', async ({ page }) => {
		await reset(page, { newCardsPerDay: 6, sessionCardCap: 6 });
		await page.goto('/session?deck=eint');
		await page.getByTestId('end-session').click();

		await expect(page.getByTestId('switch-ear-stage-2')).toBeVisible();
		await expect(page.getByTestId('switch-stage-1')).toHaveCount(0);
		// Ear stage 1 is eint and nothing else, so offering it after an eint
		// session is the same useless row as offering the deck by its own name.
		await expect(page.getByTestId('switch-ear-stage-1')).toHaveCount(0);
	});
});

/**
 * The extended keyboard: an octave and a half, drag-to-preview input.
 */
test.describe('the keyboard', () => {
	test('a drag shows the bubble and commits the key it names', async ({ page }) => {
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 3 });
		await page.goto('/session');
		await expect(page.getByTestId('card-title')).toBeVisible();

		// Press on C, slide to D, release: only D is selected — the slide is a
		// free correction, and the bubble names where the finger actually is.
		const c = (await page.locator('[data-testid="keyboard"] [data-pc="0"]').boundingBox())!;
		const d = (await page.locator('[data-testid="keyboard"] [data-pc="2"]').boundingBox())!;
		await page.mouse.move(c.x + c.width / 2, c.y + c.height - 10);
		await page.mouse.down();
		await expect(page.getByTestId('key-bubble')).toHaveText('C');
		await page.mouse.move(d.x + d.width / 2, d.y + d.height - 10, { steps: 5 });
		await expect(page.getByTestId('key-bubble')).toHaveText('D');
		await page.mouse.up();

		await expect(page.getByTestId('key-bubble')).toHaveCount(0);
		await expect(page.locator('[data-testid="keyboard"] [data-pc="2"]')).toHaveAttribute(
			'data-state',
			'selected'
		);
		await expect(page.locator('[data-testid="keyboard"] [data-pc="0"]')).toHaveAttribute(
			'data-state',
			''
		);
	});

	test('a release that drifts off the bubbled key still commits the bubbled one', async ({
		page
	}) => {
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 3 });
		await page.goto('/session');
		await expect(page.getByTestId('card-title')).toBeVisible();

		// A ~24px white key and a finger that rolls as it lifts: the pointerup can
		// land on the neighbour with no move event in between to redraw the bubble.
		// The bubble is the promise, so what it named is what commits.
		const c = (await page.locator('[data-testid="keyboard"] [data-pc="0"]').boundingBox())!;
		const d = (await page.locator('[data-testid="keyboard"] [data-pc="2"]').boundingBox())!;
		await page.mouse.move(c.x + c.width / 2, c.y + c.height - 10);
		await page.mouse.down();
		await expect(page.getByTestId('key-bubble')).toHaveText('C');
		await page.locator('[data-testid="keyboard"]').dispatchEvent('pointerup', {
			pointerId: 1,
			button: 0,
			clientX: d.x + d.width / 2,
			clientY: d.y + d.height - 10
		});

		await expect(page.locator('[data-testid="keyboard"] [data-pc="0"]')).toHaveAttribute(
			'data-state',
			'selected'
		);
		await expect(page.locator('[data-testid="keyboard"] [data-pc="2"]')).toHaveAttribute(
			'data-state',
			''
		);
	});

	test('a press in the seam between two keys still commits one', async ({ page }) => {
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 3 });
		await page.goto('/session');
		await expect(page.getByTestId('card-title')).toBeVisible();

		// The 2px flex gap belongs to no key, and the B|C seam has no black key
		// over it at any height. A tap there used to name nothing and commit
		// nothing; it now goes to whichever key it is nearer.
		const b = (await page.locator('[data-testid="keyboard"] [data-pc="11"]').boundingBox())!;
		await page.mouse.move(b.x + b.width + 0.5, b.y + b.height - 10);
		await page.mouse.down();
		await expect(page.getByTestId('key-bubble')).toHaveText('B');
		await page.mouse.up();

		await expect(page.locator('[data-testid="keyboard"] [data-pc="11"]')).toHaveAttribute(
			'data-state',
			'selected'
		);
	});

	test('a finger still down when the card changes commits nothing to the next one', async ({
		page
	}) => {
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 3 });
		await page.goto('/session');
		const first = await currentCardId(page);
		const card = expectedFor(first);
		await tapKeys(page, card.steps[0].expected);

		// A thumb resting on the keyboard while the other hand works the buttons:
		// it went down against THIS question, so its release must not answer the
		// next one. Enter, because the pointer is busy holding the key.
		const spare = (await page.locator('[data-testid="keyboard"] [data-pc="1"]').boundingBox())!;
		await page.mouse.move(spare.x + spare.width / 2, spare.y + spare.height - 10);
		await page.mouse.down();
		await page.getByTestId('check-answer').focus();
		await page.keyboard.press('Enter');
		await page.locator('[data-testid="feedback"][data-saved="true"]').waitFor();
		await expect(page.getByTestId('next-card')).toBeEnabled();
		await page.getByTestId('next-card').focus();
		await page.keyboard.press('Enter');
		await expect(page.locator('[data-card-id]')).not.toHaveAttribute('data-card-id', first);

		await page.mouse.up();
		await expect(page.locator('[data-testid="keyboard"] [data-pc="1"]')).toHaveAttribute(
			'data-state',
			''
		);
		await expect(page.getByTestId('key-bubble')).toHaveCount(0);
	});

	test('a finger still down commits nothing to the retry of the same card', async ({ page }) => {
		// Two cards, so the miss on the second one is requeued into the very next
		// slot: same card, same step, and only the deal tells the attempts apart.
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 2, sessionCardCap: 30 });
		await page.goto('/session');
		await answerCurrent(page, true);
		await page.getByTestId('next-card').click();

		const missed = await currentCardId(page);
		const card = expectedFor(missed);
		const wrong = card.steps[0].expected.map((pc) => (pc + 1) % 12);
		await tapKeys(page, wrong);

		const spare = [0, 1, 2].find((pc) => !wrong.includes(pc))!;
		const key = (await page.locator(`[data-testid="keyboard"] [data-pc="${spare}"]`).boundingBox())!;
		await page.mouse.move(key.x + key.width / 2, key.y + key.height - 10);
		await page.mouse.down();
		await page.getByTestId('check-answer').focus();
		await page.keyboard.press('Enter');
		await page.locator('[data-testid="feedback"][data-saved="true"]').waitFor();
		await expect(page.getByTestId('next-card')).toBeEnabled();
		await page.getByTestId('next-card').focus();
		await page.keyboard.press('Enter');
		// The card id cannot say the session moved on — the retry IS the same card
		// — so the reveal going away is what says it.
		await expect(page.getByTestId('feedback')).toHaveCount(0);
		await expect(page.locator('[data-card-id]')).toHaveAttribute('data-card-id', missed);

		// The finger drifts inside the same key before it lifts: the reveal is
		// taller than the answer surface and moves the keys out from under it. A
		// move is only tracked for a finger this keyboard still considers down, so
		// the drift cannot re-arm a pointer the new deal has already dropped.
		const back = (await page.locator(`[data-testid="keyboard"] [data-pc="${spare}"]`).boundingBox())!;
		await page.mouse.move(back.x + back.width / 2, back.y + back.height - 10);
		await page.mouse.up();
		await expect(
			page.locator(`[data-testid="keyboard"] [data-pc="${spare}"]`)
		).toHaveAttribute('data-state', '');
	});

	test('the bubble follows the finger still down when another lifts', async ({ page }) => {
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 3 });
		await page.goto('/session');
		await expect(page.getByTestId('card-title')).toBeVisible();

		const at = async (pc: number) => {
			const b = (await page.locator(`[data-testid="keyboard"] [data-pc="${pc}"]`).boundingBox())!;
			return { x: b.x + b.width / 2, y: b.y + b.height - 10 };
		};
		const c = { ...(await at(0)), id: 1 };
		const g = { ...(await at(7)), id: 2 };
		const cdp = await page.context().newCDPSession(page);
		const touch = (type: string, touchPoints: unknown[]) =>
			cdp.send('Input.dispatchTouchEvent', { type, touchPoints } as never);

		await touch('touchStart', [c]);
		await expect(page.getByTestId('key-bubble')).toHaveText('C');
		await touch('touchStart', [c, g]);
		await expect(page.getByTestId('key-bubble')).toHaveText('G');

		// Lift the G finger only. A bubble left naming it would describe neither
		// the key under the hand nor the one the next release will commit.
		await touch('touchEnd', [g]);
		await expect(page.getByTestId('key-bubble')).toHaveText('C');

		await touch('touchEnd', []);
		await expect(page.getByTestId('key-bubble')).toHaveCount(0);
	});

	test('a black key names both spellings, never one', async ({ page }) => {
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 3 });
		await page.goto('/session');
		await expect(page.getByTestId('card-title')).toBeVisible();

		const fs = (await page.locator('[data-testid="keyboard"] [data-pc="6"]').boundingBox())!;
		await page.mouse.move(fs.x + fs.width / 2, fs.y + fs.height / 2);
		await page.mouse.down();
		// Naming only one spelling would hand over the D♭-versus-C♯ decision.
		await expect(page.getByTestId('key-bubble')).toHaveText('F♯ · G♭');
		await page.mouse.up();
	});

	test('answers with Enter and Space alone, no pointer at all', async ({ page }) => {
		// The only non-pointer way to answer a keys card, and it hangs on a single
		// branch: click with detail 0. Every other test here clicks, which commits
		// on pointerup and would stay green with that branch gone — leaving a
		// switch or keyboard user focusing keys that never select.
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 3 });
		await page.goto('/session');
		const card = expectedFor(await currentCardId(page));
		const [first, second] = card.steps[0].expected;

		await page.locator(`[data-testid="keyboard"] [data-pc="${first}"]`).press('Enter');
		await page.locator(`[data-testid="keyboard"] [data-pc="${second}"]`).press(' ');
		for (const pc of [first, second]) {
			await expect(page.locator(`[data-testid="keyboard"] [data-pc="${pc}"]`)).toHaveAttribute(
				'data-state',
				'selected'
			);
		}

		await page.getByTestId('check-answer').press('Enter');
		await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'true');
	});

	test('flanking copies light together with their home key', async ({ page }) => {
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 3 });
		await page.goto('/session');
		await expect(page.getByTestId('card-title')).toBeVisible();

		// Tap home G: the flanking G below is the same pitch class and says so.
		await tapKeys(page, [7]);
		await expect(page.locator('[data-testid="keyboard"] [data-pc="7"]')).toHaveAttribute(
			'data-state',
			'selected'
		);
		await expect(
			page.locator('[data-testid="keyboard"] [data-flank-pc="7"]')
		).toHaveAttribute('data-state', 'selected');
	});
});
