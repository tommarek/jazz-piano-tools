import { expect, test } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { answerCurrent, reset } from './helpers';
import { buildCatalogue } from '../../src/lib/music/cards';

/** Reads whatever the app just downloaded. */
async function downloadJson(page: import('@playwright/test').Page, trigger: () => Promise<void>) {
	const [download] = await Promise.all([page.waitForEvent('download'), trigger()]);
	const path = await download.path();
	return { name: download.suggestedFilename(), data: JSON.parse(await readFile(path, 'utf8')) };
}

test.describe('data export', () => {
	test('produces valid JSON containing the review log', async ({ page }) => {
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 5 });

		await page.goto('/session');
		await answerCurrent(page, true);
		await page.getByTestId('next-card').click();
		await answerCurrent(page, false);
		await page.getByTestId('end-session').click();
		await expect(page.getByTestId('session-summary')).toBeVisible();

		await page.goto('/settings');
		const { name, data } = await downloadJson(page, () => page.getByTestId('export-link').click());

		expect(name).toMatch(/^voicings-\d{4}-\d{2}-\d{2}\.json$/);
		expect(data.version).toBe(1);
		expect(Number.isNaN(Date.parse(data.exportedAt))).toBe(false);
		// Derived, not hard-coded, so growing the deck does not fail the export test.
		expect(data.cards.length).toBe(buildCatalogue().length);
		expect(data.reviews.length).toBe(2);
		expect(data.reviews.map((r: { correct: number }) => r.correct)).toEqual([1, 0]);
		expect(data.settings.activeCardTypes).toEqual(['gt']);

		// Every review points at a real card, so the log can rebuild the schedule.
		const ids = new Set(data.cards.map((c: { id: string }) => c.id));
		for (const review of data.reviews) expect(ids.has(review.card_id)).toBe(true);
	});

	test('round-trips through import, which is the only way to move phones', async ({ page }) => {
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 5 });
		await page.goto('/session');
		for (let i = 0; i < 3; i++) {
			await answerCurrent(page, true);
			await page.getByTestId('next-card').click();
		}
		await page.goto('/settings');
		const { data } = await downloadJson(page, () => page.getByTestId('export-link').click());
		expect(data.reviews.length).toBe(3);

		// Wipe, then restore from the backup.
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 5 });
		await page.goto('/');
		await expect(page.getByTestId('today-count')).toHaveText('0');

		await page.goto('/settings');
		// Importing reloads the app so it reopens the restored database; racing
		// that reload with a navigation aborts it.
		await Promise.all([
			page.waitForEvent('load'),
			page.setInputFiles('input[type="file"]', {
				name: 'backup.json',
				mimeType: 'application/json',
				buffer: Buffer.from(JSON.stringify(data))
			})
		]);

		await page.goto('/');
		await expect(page.getByTestId('today-count')).toHaveText('3');
	});
});
