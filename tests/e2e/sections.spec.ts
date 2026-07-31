import { expect, test } from '@playwright/test';
import { answerCurrent, currentCardId, reset } from './helpers';

/**
 * Theory and ear are separate sections, not two decks in one list.
 *
 * The property under test is that nothing crosses: a theory session never
 * deals a sound-only card, an ear session never deals a written one, and the
 * two paths gate independently. They share a database and a scheduler and
 * nothing else.
 */
test.describe('the two sections', () => {
	test('the theory session never deals an ear card', async ({ page }) => {
		await reset(page, { newCardsPerDay: 20, sessionCardCap: 20 });
		await page.goto('/');
		await page.getByTestId('start-session').click();

		for (let i = 0; i < 8; i++) {
			expect(await currentCardId(page)).not.toMatch(/^e(int|qal):/);
			await answerCurrent(page, true);
			await page.getByTestId('next-card').click();
		}
	});

	test('the ear session deals nothing else', async ({ page }) => {
		await reset(page, { newCardsPerDay: 20, sessionCardCap: 20 });
		await page.goto('/ear');
		await page.getByTestId('start-ear').click();

		await expect(page.getByTestId('session-deck')).toHaveText('Ear training');
		for (let i = 0; i < 6; i++) {
			expect(await currentCardId(page)).toMatch(/^e(int|qal):/);
			await answerCurrent(page, true);
			await page.getByTestId('next-card').click();
		}
	});

	test('each section counts only its own cards', async ({ page }) => {
		// Switch one section's drills off entirely: its counter has to go to zero
		// while the other's does not. Comparing two non-zero numbers proves
		// nothing — a counter built over both sections would pass that.
		await reset(page, { activeCardTypes: ['eint', 'eqal'], newCardsPerDay: 6 });
		await page.goto('/');
		await expect(page.getByTestId('due-count')).toHaveText('0');
		await page.goto('/ear');
		await expect(page.getByTestId('ear-due-count')).not.toHaveText('0');

		await reset(page, { activeCardTypes: ['gt', 'ivl'], newCardsPerDay: 6 });
		await page.goto('/');
		await expect(page.getByTestId('due-count')).not.toHaveText('0');
		await page.goto('/ear');
		await expect(page.getByTestId('ear-due-count')).toHaveText('0');
	});

	test('neither section can spend the other’s new cards', async ({ page }) => {
		// Theory is the screen the app opens on. With one shared allowance, a
		// learner who starts there spent all of it before ever tapping Ear — every
		// day, so the ear section never introduced a first card at all.
		await reset(page, { newCardsPerDay: 4, sessionCardCap: 4 });
		await page.goto('/');
		await page.getByTestId('start-session').click();
		for (let i = 0; i < 4; i++) {
			await answerCurrent(page, true);
			await page.getByTestId('next-card').click();
		}

		await page.goto('/ear');
		await expect(page.getByTestId('ear-due-count')).not.toHaveText('0');
		await page.getByTestId('start-ear').click();
		expect(await currentCardId(page)).toMatch(/^e(int|qal):/);
	});

	test('the ear path gates on its own, not on the theory one', async ({ page }) => {
		// Every theory stage open, ear still on its first: qualities-by-ear is not
		// something a rootless voicing has ever demonstrated.
		await reset(page, { unlockedStages: 3, earUnlockedStages: 1, newCardsPerDay: 8 });
		await page.goto('/ear');

		// Marked as ahead of the ear path — not as something the theory path opened.
		await expect(page.getByTestId('ear-decks')).toContainText('ahead');
		await expect(page.getByTestId('ear-gate')).toContainText('heard intervals');
		// Drillable on request, like every other deck; it is the mix it stays out
		// of, and the ear section's own Start is what that mix means here.
		await page.goto('/session?deck=eqal');
		expect(await currentCardId(page)).toMatch(/^eqal:/);
		await page.goto('/ear');
		await page.getByTestId('start-ear').click();
		for (let i = 0; i < 3; i++) {
			expect(await currentCardId(page)).toMatch(/^eint:/);
			await answerCurrent(page, true);
			await page.getByTestId('next-card').click();
		}
	});

	test('ear training is its own tab, and says so when sound is off', async ({ page }) => {
		await reset(page, { soundEnabled: false, newCardsPerDay: 8 });
		await page.goto('/');
		await page.getByRole('link', { name: 'Ear' }).click();

		await expect(page).toHaveURL(/\/ear$/);
		await expect(page.getByTestId('ear-no-sound')).toContainText('Settings');
		// The theory section is unaffected by sound being off.
		await page.goto('/');
		await expect(page.getByTestId('start-session')).toHaveText('Start');
	});

	test('the ear figures stay out of the theory ones on Progress', async ({ page }) => {
		await reset(page, { newCardsPerDay: 20, sessionCardCap: 20 });
		await page.goto('/ear');
		await page.getByTestId('start-ear').click();
		for (let i = 0; i < 3; i++) {
			await answerCurrent(page, true);
			await page.getByTestId('next-card').click();
		}
		await page.getByTestId('end-session').click();

		await page.goto('/progress');
		// The ear block reports those three; the theory charts above have no
		// reviews to draw at all, because none of them were theory cards.
		await expect(page.getByTestId('ear-stats')).toContainText('Intervals by ear');
		await expect(page.getByTestId('ear-stats')).not.toContainText('No ear cards answered yet');
		// Both theory charts empty and only the ear one drawn: the section filter
		// on the day series is what this test is actually for, and asserting the
		// ear block alone let the filter be dropped without anything failing.
		await expect(page.getByTestId('chart-empty')).toHaveCount(2);
	});
});

/**
 * Looking inside a deck. The count on a picker row is the way in — the words
 * "240 cards" already promise a list, so they are the link to it.
 */
test.describe('browsing a deck', () => {
	test('opens from the picker and lists what is in it', async ({ page }) => {
		await reset(page, { unlockedStages: 3, newCardsPerDay: 6 });
		await page.goto('/');
		await page.getByTestId('browse-stage-1').click();

		await expect(page).toHaveURL(/\/deck\/stage-1$/);
		await expect(page.getByRole('heading', { name: 'Guide tones', exact: true })).toBeVisible();
		// Grouped by the drills inside the stage.
		await expect(page.getByTestId('browse-group-gt')).toBeVisible();
		await expect(page.getByTestId('browse-group-ivl')).toBeVisible();

		// And it starts the deck it is showing.
		await page.getByTestId('start-deck').click();
		await expect(page.getByTestId('session-deck')).toHaveText('Guide tones');
	});

	test('shows each card exactly as it is asked and answered', async ({ page }) => {
		await reset(page, { unlockedStages: 3 });
		await page.goto('/deck/gt');

		// Question and answer together, no tap. This is the one screen in the app
		// where that is true, and it is what makes it useful for checking a deck.
		const row = page.getByTestId('card-gt:C:maj7');
		await expect(row).toContainText('Cmaj7');
		await expect(page.getByTestId('answer-gt:C:maj7')).toContainText('E');
	});

	test('an ear card carries its sound, because that is its question', async ({ page }) => {
		await reset(page, { unlockedStages: 3, earUnlockedStages: 2 });
		await page.goto('/deck/eint');

		// Printing "two notes, low to high" is a description of the question, not
		// the question — so the row plays it.
		await expect(page.getByTestId('play-eint:C:P5')).toBeVisible();
		await expect(page.getByTestId('answer-eint:C:P5')).toContainText('perfect 5th');
	});

	test('and has no rows at all when playback is off', async ({ page }) => {
		// Not "the ♪ button is hidden": with the sound off the ear drills leave
		// liveDeckTypes, so the deck is empty and there is no row to hide it on.
		await reset(page, { unlockedStages: 3, earUnlockedStages: 2, soundEnabled: false });
		await page.goto('/deck/eint');
		// And it says which switch did it: the drill is still ticked, so blaming
		// the drill list would send the learner to the wrong row of Settings.
		await expect(page.getByTestId('deck-browse-empty')).toContainText('Play the answer');
		await expect(page.getByTestId('card-eint:C:P5')).toHaveCount(0);
	});

	test('filters down to what is weak', async ({ page }) => {
		await reset(page, { unlockedStages: 3 });
		await page.goto('/deck/mode');

		await page.getByTestId('filter-automatic').click();
		// Nothing is automatic on a fresh install, and the list says so rather
		// than rendering an empty page.
		await expect(page.getByTestId('filter-empty')).toBeVisible();

		await page.getByTestId('filter-weak').click();
		await expect(page.getByTestId('browse-group-mode')).toBeVisible();
	});

	test('the pre-split "all" slug browses the theory section', async ({ page }) => {
		// ?deck=all still starts a theory session, so /deck/all has to browse one
		// rather than 404 — it is an old slug, not an unknown one.
		await reset(page);
		await page.goto('/deck/all');
		await expect(page).toHaveURL(/\/deck\/theory$/);
		await expect(page.getByTestId('error-page')).toHaveCount(0);
	});

	test('a deck slug that does not exist is a 404, not a different deck', async ({ page }) => {
		// parseDeckSlug falls back to the theory section so a stale link still
		// starts a session; showing a different deck than the URL names would be
		// lying about what is on screen.
		await reset(page);
		await page.goto('/deck/nonsense');
		await expect(page.getByTestId('error-page')).toBeVisible();
	});
});
