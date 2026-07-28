import { expect, test } from '@playwright/test';
import { answerCurrent, currentCardId, expectedFor, reset, tapKeys } from './helpers';

test.describe('the critical path', () => {
	test.beforeEach(async ({ page }) => {
		// A narrow deck keeps the queue predictable without weakening the flow test.
		await reset(page, {
			activeCardTypes: ['s2n'],
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

		await answerCurrent(page, false);
		const feedback = page.getByTestId('feedback');
		await expect(feedback).toHaveAttribute('data-correct', 'false');
		await expect(page.getByTestId('answer-text')).toHaveText(card.answerText);
		await expect(feedback).toContainText("You'll see this one again");

		// It must reappear before the session ends.
		const seen: string[] = [];
		for (let i = 0; i < 8; i++) {
			await page.getByTestId('next-card').click();
			if (!(await page.getByTestId('card-title').isVisible())) break;
			const id = await currentCardId(page);
			seen.push(id);
			await answerCurrent(page, true);
		}
		expect(seen).toContain(firstId);
	});
});

test.describe('empty sessions', () => {
	test('a speed round with nothing mastered explains itself', async ({ page }) => {
		await reset(page, { activeCardTypes: ['s2n'], newCardsPerDay: 5 });
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
		await reset(page, { activeCardTypes: ['s2n'], newCardsPerDay: 0 });
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
});

test.describe('visualise-then-place', () => {
	test('hides the keyboard for the whole delay', async ({ page }) => {
		await reset(page, {
			activeCardTypes: ['s2n'],
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
	test('accepts a chord named from the keys shown', async ({ page }) => {
		await reset(page, { activeCardTypes: ['n2s'], newCardsPerDay: 3 });
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
