import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';
import { answerCurrent, reset } from './helpers';

/** WCAG 2.2 target size (minimum) is 24px; this app aims at 44px for the thumb. */
const MIN_TAP = 44;

async function noHorizontalScroll(page: Page) {
	const overflow = await page.evaluate(
		() => document.documentElement.scrollWidth - document.documentElement.clientWidth
	);
	expect(overflow).toBeLessThanOrEqual(1);
}

async function axeScan(page: Page, context: string) {
	const results = await new AxeBuilder({ page })
		.withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
		.analyze();
	expect(
		results.violations.map((v) => `${context}: ${v.id} — ${v.help}`),
		JSON.stringify(results.violations, null, 2)
	).toEqual([]);
}

test.describe('mobile and accessibility', () => {
	test.beforeEach(async ({ page }) => {
		await reset(page, { activeCardTypes: ['s2n'], newCardsPerDay: 10 });
	});

	for (const [name, path] of [
		['today', '/'],
		['progress', '/progress'],
		['settings', '/settings'],
		['reference index', '/reference'],
		['reference topic', '/reference/rootless'],
		['reference tables', '/reference/diatonic']
	] as const) {
		test(`${name} has no axe violations and does not scroll sideways`, async ({ page }) => {
			await page.goto(path);
			await noHorizontalScroll(page);
			await axeScan(page, name);
		});
	}

	// Every answer surface gets scanned, not just the keyboard: the pickers are
	// dense grids of small buttons and are exactly where contrast slips.
	for (const type of ['n2s', 'dia', 'mode', 'ext', 'chain', 'eint'] as const) {
		test(`the ${type} answer surface is accessible`, async ({ page }) => {
			await reset(page, { activeCardTypes: [type], newCardsPerDay: 4 });
			await page.goto('/session');
			await expect(page.getByTestId('card-title')).toBeVisible();
			await noHorizontalScroll(page);
			await axeScan(page, `session:${type}`);
		});
	}

	test('rootless answer surface is accessible', async ({ page }) => {
		await reset(page, {
			activeCardTypes: ['rootless'],
			newCardsPerDay: 4,
			unlockedStages: 4
		});
		await page.goto('/session');
		await expect(page.getByTestId('card-title')).toBeVisible();
		await noHorizontalScroll(page);
		await axeScan(page, 'session:rootless');
	});

	test('the reference sheet over a session is accessible', async ({ page }) => {
		await reset(page, { activeCardTypes: ['s2n'], newCardsPerDay: 4 });
		await page.goto('/session');
		await answerCurrent(page, true);
		await page.getByTestId('explain').click();
		await expect(page.getByTestId('reference-sheet')).toBeVisible();
		await noHorizontalScroll(page);
		await axeScan(page, 'reference-sheet');
	});

	test('the keyboard still fits on a 320dp phone', async ({ page }) => {
		// Seven 44px keys need more width than the page padding leaves at 320dp.
		// The Android emulator caught the last key hanging off the screen.
		await page.setViewportSize({ width: 320, height: 640 });
		await page.goto('/session');
		await expect(page.getByTestId('card-title')).toBeVisible();
		await noHorizontalScroll(page);

		for (const pc of [0, 11]) {
			const box = (await page
				.locator(`[data-testid="keyboard"] [data-pc="${pc}"]`)
				.boundingBox())!;
			expect(box, `white key ${pc} missing`).not.toBeNull();
			// Fully on screen, both edges.
			expect(box.x).toBeGreaterThanOrEqual(0);
			expect(box.x + box.width).toBeLessThanOrEqual(320);
			expect(box.width).toBeGreaterThanOrEqual(MIN_TAP);
		}
	});

	test('session screen is thumb-usable on an iPhone', async ({ page }) => {
		await page.goto('/session');
		await expect(page.getByTestId('card-title')).toBeVisible();
		await noHorizontalScroll(page);
		await axeScan(page, 'session');

		const viewport = page.viewportSize()!;

		// White keys must clear the tap-target size.
		for (const pc of [0, 2, 4, 5, 7, 9, 11]) {
			const box = await page.locator(`[data-testid="keyboard"] [data-pc="${pc}"]`).boundingBox();
			expect(box, `white key ${pc} missing`).not.toBeNull();
			expect(box!.width, `white key ${pc} width`).toBeGreaterThanOrEqual(MIN_TAP);
			expect(box!.height, `white key ${pc} height`).toBeGreaterThanOrEqual(MIN_TAP);
		}

		// Black keys are narrower than a white key by design; they still clear 44px
		// in both directions because they are tall.
		for (const pc of [1, 3, 6, 8, 10]) {
			const box = await page.locator(`[data-testid="keyboard"] [data-pc="${pc}"]`).boundingBox();
			expect(box, `black key ${pc} missing`).not.toBeNull();
			expect(box!.width, `black key ${pc} width`).toBeGreaterThanOrEqual(MIN_TAP);
			expect(box!.height, `black key ${pc} height`).toBeGreaterThanOrEqual(MIN_TAP);
		}

		// The whole answer surface sits in the reachable lower part of the screen.
		const keyboard = (await page.getByTestId('keyboard').boundingBox())!;
		expect(keyboard.y).toBeGreaterThan(viewport.height * 0.3);
		expect(keyboard.y + keyboard.height).toBeLessThanOrEqual(viewport.height);

		const check = (await page.getByTestId('check-answer').boundingBox())!;
		expect(check.height).toBeGreaterThanOrEqual(MIN_TAP);
		expect(check.y + check.height).toBeLessThanOrEqual(viewport.height);
	});
});
