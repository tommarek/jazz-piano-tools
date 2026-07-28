import { expect, test } from '@playwright/test';
import { answerCurrent, currentCardId, reset } from './helpers';

/**
 * Offline is no longer a mode — it is how the app works. These tests cut the
 * network entirely and check that nothing depends on it, and that the on-device
 * database actually survives a restart.
 */
test.describe('no network at all', () => {
	test('a whole session runs with the network cut', async ({ page, context }) => {
		await reset(page, { activeCardTypes: ['s2n'], newCardsPerDay: 10, sessionCardCap: 10 });
		await page.goto('/');

		await context.setOffline(true);

		await page.getByTestId('start-session').click();
		await expect(page.getByTestId('card-title')).toBeVisible();
		for (let i = 0; i < 3; i++) {
			await answerCurrent(page, true);
			await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'true');
			await page.getByTestId('next-card').click();
		}
		await page.getByTestId('end-session').click();
		await expect(page.getByTestId('summary-answered')).toHaveText('3');

		// Recorded straight to the device: no queue, no sync, nothing pending.
		await page.getByRole('link', { name: 'Done' }).click();
		await expect(page.getByTestId('today-count')).toHaveText('3');
	});

	test('progress survives closing and reopening the app', async ({ page }) => {
		await reset(page, { activeCardTypes: ['s2n'], newCardsPerDay: 10, sessionCardCap: 10 });
		await page.goto('/session');
		const firstId = await currentCardId(page);
		await answerCurrent(page, true);
		await page.getByTestId('next-card').click();
		await answerCurrent(page, true);

		// A full reload is the closest thing a browser has to a cold app start:
		// the in-memory database is gone and has to come back from storage.
		await page.reload();
		await page.goto('/');
		await expect(page.getByTestId('today-count')).toHaveText('2');

		// And it is the same database, not a fresh one that happens to count.
		await page.goto('/session');
		await expect(page.getByTestId('card-title')).toBeVisible();
		expect(await currentCardId(page)).not.toBe(firstId);
	});

	test('the app shell loads from the service worker with no network', async ({ page, context }) => {
		await page.goto('/');
		await page.waitForFunction(() => navigator.serviceWorker?.controller !== null, null, {
			timeout: 20_000
		});

		await context.setOffline(true);
		await page.reload();

		// Not the browser's offline error page.
		await expect(page.locator('nav')).toBeVisible();
		await expect(page.getByRole('heading', { name: 'Voicings', exact: true })).toBeVisible();
	});
});
