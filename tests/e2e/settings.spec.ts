import { expect, test } from '@playwright/test';
import { currentCardId, expectedFor, reset } from './helpers';

/**
 * The deck the queue actually draws from is narrower than the ticked list:
 * locked stages and the sound switch both take drills out of it. Saving a
 * combination that leaves nothing is how the app ends up telling someone to
 * come back tomorrow forever.
 */
test.describe('settings cannot empty the deck', () => {
	test('refuses a save where every drill left on is in a locked stage', async ({ page }) => {
		await reset(page, { unlockedStages: 1, newCardsPerDay: 8 });
		await page.goto('/settings');

		// Both sections: the ear drills are on their own ladder, so switching the
		// open theory stage off no longer leaves the ear ones locked with it.
		for (const type of ['gt', 'gtn', 'ivl', 'eint', 'eqal']) {
			await page.getByTestId(`cardtype-${type}`).uncheck();
		}
		await page.getByTestId('save-settings').click();

		await expect(page.getByRole('alert')).toContainText('stage that is not open yet');
		// And nothing was written: Today still has a session to offer.
		await page.goto('/');
		await expect(page.getByTestId('due-count')).not.toHaveText('0');
	});

	test('refuses a save that leaves only the ear drills with sound off', async ({ page }) => {
		await reset(page, { activeCardTypes: ['eint'], newCardsPerDay: 8 });
		await page.goto('/settings');

		await page.getByTestId('sound-enabled').uncheck();
		await page.getByTestId('save-settings').click();

		await expect(page.getByRole('alert')).toContainText('ear');
	});

	test('refuses a save whose qualities leave the drills on offer with no card', async ({
		page
	}) => {
		// Both ticked lists are legal on their own; they just have nothing in
		// common. A chain is answered with all three of its chords, so dropping
		// the major tonic and the minor one leaves no chain of either mode.
		await reset(page, { activeCardTypes: ['chain'], unlockedStages: 2, newCardsPerDay: 8 });
		await page.goto('/settings');

		await page.getByTestId('quality-maj7').uncheck();
		await page.getByTestId('quality-mMaj7').uncheck();
		await page.getByTestId('save-settings').click();

		await expect(page.getByRole('alert')).toContainText('deck would be empty');
		await page.goto('/');
		await expect(page.getByTestId('due-count')).not.toHaveText('0');
	});

	test('accepts an ear-only deck: the two sections are separate practices', async ({ page }) => {
		// The guard used to ask the theory deck on its own, so wanting nothing but
		// ear training was refused — with a message about chord qualities, which
		// had nothing to do with it.
		await reset(page, { activeCardTypes: ['gt', 'eint', 'eqal'], newCardsPerDay: 8 });
		await page.goto('/settings');

		await page.getByTestId('cardtype-gt').uncheck();
		await page.getByTestId('save-settings').click();

		await expect(page.getByRole('status')).toContainText('Saved');
		await page.goto('/ear');
		await expect(page.getByTestId('start-ear')).toHaveText('Start');
	});

	test('will not let a locked drill stand in for a real choice', async ({ page }) => {
		await reset(page, { unlockedStages: 1 });
		await page.goto('/settings');

		await expect(page.getByTestId('cardtype-gt')).toBeEnabled();
		await expect(page.getByTestId('cardtype-rootless')).toBeDisabled();
	});
});

test.describe('a deck filtered down to nothing', () => {
	test('says so on Today rather than promising tomorrow', async ({ page }) => {
		// Only a locked stage is on, so no amount of waiting produces a card.
		await reset(page, { activeCardTypes: ['rootless'], unlockedStages: 1 });
		await page.goto('/');

		await expect(page.getByTestId('deck-empty')).toContainText('Settings');
		await expect(page.getByTestId('start-session')).toHaveText('Deck is empty');
	});
});

/**
 * Answering on tap. The saving is one tap per card, so the whole feature is
 * whether the pick submits — and, just as importantly, whether it stays out of
 * the way of the cards where a first tap is only half an answer.
 */
test.describe('answer on tap', () => {
	test('a one-tap drill submits on the pick, with no Check', async ({ page }) => {
		await reset(page, {
			activeCardTypes: ['mode'],
			unlockedStages: 3,
			instantAnswer: true,
			newCardsPerDay: 4
		});
		await page.goto('/');
		await page.getByTestId('start-session').click();

		const card = expectedFor(await currentCardId(page));
		await page.getByTestId(`mode-${card.expectedMode}`).click();

		// Graded and durably written without the Check button being touched.
		await expect(page.locator('[data-testid="feedback"][data-saved="true"]')).toBeVisible();
		await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'true');
		await expect(page.getByTestId('next-card')).toBeVisible();
	});

	test('leaves a two-part answer alone — a quality is not an answer by itself', async ({
		page
	}) => {
		// The diatonic drill asks for a root as well, so submitting on the first
		// tap would grade half an answer.
		await reset(page, {
			activeCardTypes: ['dia'],
			unlockedStages: 3,
			instantAnswer: true,
			newCardsPerDay: 4
		});
		await page.goto('/');
		await page.getByTestId('start-session').click();

		const card = expectedFor(await currentCardId(page));
		await page.getByTestId(`quality-${card.expectedChord!.quality}`).click();
		await expect(page.getByTestId('feedback')).toBeHidden();
		await expect(page.getByTestId('check-answer')).toBeVisible();
	});

	test('is off unless asked for: the pick waits for Check', async ({ page }) => {
		await reset(page, { activeCardTypes: ['mode'], unlockedStages: 3, newCardsPerDay: 4 });
		await page.goto('/');
		await page.getByTestId('start-session').click();

		const card = expectedFor(await currentCardId(page));
		await page.getByTestId(`mode-${card.expectedMode}`).click();
		await expect(page.getByTestId('feedback')).toBeHidden();
		await page.getByTestId('check-answer').click();
		await expect(page.getByTestId('feedback')).toBeVisible();
	});
});
