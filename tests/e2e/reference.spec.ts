import { expect, test } from '@playwright/test';
import { answerCurrent, currentCardId, expectedFor, reset } from './helpers';
import { TOPICS } from '../../src/lib/content/reference';
import { readFile } from 'node:fs/promises';

test.describe('the reference section', () => {
	test.beforeEach(async ({ page }) => {
		await reset(page, { activeCardTypes: ['s2n'], newCardsPerDay: 6 });
	});

	test('is reachable from the main nav and lists every topic', async ({ page }) => {
		await page.goto('/');
		await page.getByRole('link', { name: 'Reference' }).click();
		await expect(page).toHaveURL('/reference');

		for (const topic of TOPICS) {
			await expect(page.getByTestId(`topic-${topic.id}`)).toContainText(topic.title);
		}
	});

	test('opens a topic and links on to related ones', async ({ page }) => {
		await page.goto('/reference');
		await page.getByTestId('topic-shells').click();
		await expect(page.getByRole('heading', { name: 'Shell voicings' })).toBeVisible();
		// The content is really there, not just a stub.
		await expect(page.getByText('root plus either the 3rd or the 7th')).toBeVisible();

		await page.getByRole('link', { name: 'guide tones' }).click();
		await expect(page).toHaveURL('/reference/guide-tones');
		await expect(page.getByRole('heading', { name: 'Guide tones and voice leading' })).toBeVisible();
	});

	test('shows an error for a topic that does not exist', async ({ page }) => {
		// The app is a single-page bundle, so there is no HTTP 404 to assert —
		// the router raises the error and SvelteKit renders its error page.
		await page.goto('/reference/not-a-topic');
		await expect(page.getByText('No such topic')).toBeVisible();
	});
});

test.describe('explaining a card', () => {
	test.beforeEach(async ({ page }) => {
		await reset(page, { activeCardTypes: ['s2n'], newCardsPerDay: 6 });
	});

	test('is not offered until the answer is on screen', async ({ page }) => {
		await page.goto('/session');
		await expect(page.getByTestId('card-title')).toBeVisible();
		// Looking it up mid-attempt would make this a reading exercise.
		await expect(page.getByTestId('explain')).toHaveCount(0);

		await answerCurrent(page, true);
		await expect(page.getByTestId('explain')).toBeVisible();
	});

	test('opens over the session without losing the queue', async ({ page }) => {
		await page.goto('/session');
		const firstId = await currentCardId(page);

		await answerCurrent(page, true);
		await page.getByTestId('explain').click();

		const sheet = page.getByTestId('reference-sheet');
		await expect(sheet).toBeVisible();
		await expect(sheet).toContainText('Shell voicings');

		await page.getByTestId('close-reference').click();
		await expect(sheet).toBeHidden();

		// Still the same card, still mid-session.
		expect(await currentCardId(page)).toBe(firstId);
		await page.getByTestId('next-card').click();
		await expect(page.getByTestId('card-title')).toBeVisible();
	});

	test('closes on Escape', async ({ page }) => {
		await page.goto('/session');
		await answerCurrent(page, true);
		await page.getByTestId('explain').click();
		await expect(page.getByTestId('reference-sheet')).toBeVisible();

		await page.keyboard.press('Escape');
		await expect(page.getByTestId('reference-sheet')).toBeHidden();
	});
});

test.describe('"No idea"', () => {
	test.beforeEach(async ({ page }) => {
		await reset(page, { activeCardTypes: ['s2n'], newCardsPerDay: 6 });
	});

	test('reveals the answer without making you guess wrong first', async ({ page }) => {
		await page.goto('/session');
		const card = expectedFor(await currentCardId(page));

		await page.getByTestId('give-up').click();

		const feedback = page.getByTestId('feedback');
		await expect(feedback).toBeVisible();
		await expect(feedback).toContainText('Here it is');
		await expect(page.getByTestId('answer-text')).toHaveText(card.answerText);
		await expect(page.getByTestId('explain')).toBeVisible();
	});

	test('counts as a lapse and brings the card back', async ({ page }) => {
		await page.goto('/session');
		const firstId = await currentCardId(page);
		await page.getByTestId('give-up').click();
		await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'false');

		const seen: string[] = [];
		for (let i = 0; i < 8; i++) {
			await page.getByTestId('next-card').click();
			if (!(await page.getByTestId('card-title').isVisible())) break;
			seen.push(await currentCardId(page));
			await answerCurrent(page, true);
		}
		expect(seen).toContain(firstId);

		// And it was recorded as a real lapse, not silently dropped: the export is
		// the only window onto the review log now that there is no server.
		await page.goto('/settings');
		const [download] = await Promise.all([
			page.waitForEvent('download'),
			page.getByTestId('export-link').click()
		]);
		const data = JSON.parse(await readFile(await download.path(), 'utf8'));
		const lapse = data.reviews.find(
			(r: { card_id: string; correct: number }) => r.card_id === firstId && r.correct === 0
		);
		expect(lapse).toBeDefined();
		expect(JSON.parse(lapse.answer_given)).toEqual({ gaveUp: true });
	});
});
