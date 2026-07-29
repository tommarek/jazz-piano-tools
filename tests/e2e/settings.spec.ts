import { expect, test } from '@playwright/test';
import { reset } from './helpers';

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

		for (const type of ['s2n', 'n2s', 'ivl', 'eint']) {
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

	test('will not let a locked drill stand in for a real choice', async ({ page }) => {
		await reset(page, { unlockedStages: 1 });
		await page.goto('/settings');

		await expect(page.getByTestId('cardtype-s2n')).toBeEnabled();
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
