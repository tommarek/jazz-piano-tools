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
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 10 });
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
	for (const type of ['gtn', 'dia', 'mode', 'ext', 'chain', 'eint'] as const) {
		test(`the ${type} answer surface is accessible`, async ({ page }) => {
			await reset(page, { activeCardTypes: [type], newCardsPerDay: 4 });
			// The ear drills are their own section now, so their session is too.
			await page.goto(type === 'eint' ? '/session?deck=ear' : '/session');
			await expect(page.getByTestId('card-title')).toBeVisible();
			await noHorizontalScroll(page);
			await axeScan(page, `session:${type}`);
		});
	}

	// The reset above opens every stage, so the loop's settings scan never saw a
	// locked drill row — which is exactly the row that had been dimmed with
	// opacity until its 11px hint sat at 3.1:1.
	test('settings is accessible with the path still locked', async ({ page }) => {
		await reset(page, { unlockedStages: 1, earUnlockedStages: 1 });
		await page.goto('/settings');
		await expect(page.getByTestId('cardtype-ext')).toBeDisabled();
		await noHorizontalScroll(page);
		await axeScan(page, 'settings:locked');
	});

	// Not in the loop above: both screens have to be populated to be worth
	// scanning, and the loop's reset leaves one drill on.
	test('the ear section is accessible', async ({ page }) => {
		await reset(page, { activeCardTypes: ['eint', 'eqal'] });
		await page.goto('/ear');
		await expect(page.getByTestId('ear-decks')).toBeVisible();
		await noHorizontalScroll(page);
		await axeScan(page, 'ear');
	});

	// Dense rows of small controls, which is where contrast slips: the filter
	// group, and an ear deck's per-row ♪ buttons.
	for (const [name, path, type] of [
		['read', '/deck/gt', 'gt'],
		['heard', '/deck/eint', 'eint']
	] as const) {
		test(`browsing a ${name} deck is accessible`, async ({ page }) => {
			await reset(page);
			await page.goto(path);
			await expect(page.getByTestId(`browse-group-${type}`)).toBeVisible();
			await noHorizontalScroll(page);
			await axeScan(page, `deck:${name}`);
		});
	}

	test('a wrong-key reveal is accessible', async ({ page }) => {
		// The scans above all answer correctly, so axe had never seen a felt-filled
		// key: the wrong-key ink used to sit at 4.13:1 behind the 12px letter and
		// nothing in the suite could say so.
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 4 });
		await page.goto('/session');
		await answerCurrent(page, false);
		await expect(page.getByTestId('feedback')).toHaveAttribute('data-correct', 'false');
		await expect(
			page.locator('[data-testid="keyboard"] [data-state="wrong"]').first()
		).toBeVisible();
		await noHorizontalScroll(page);
		await axeScan(page, 'session:wrong-keys');
	});

	test('rootless answer surface is accessible', async ({ page }) => {
		await reset(page, {
			activeCardTypes: ['rootless'],
			newCardsPerDay: 4,
			unlockedStages: 3
		});
		await page.goto('/session');
		await expect(page.getByTestId('card-title')).toBeVisible();
		await noHorizontalScroll(page);
		await axeScan(page, 'session:rootless');
	});

	test('the reference sheet over a session is accessible', async ({ page }) => {
		await reset(page, { activeCardTypes: ['gt'], newCardsPerDay: 4 });
		await page.goto('/session');
		await answerCurrent(page, true);
		await page.getByTestId('explain').click();
		await expect(page.getByTestId('reference-sheet')).toBeVisible();
		await noHorizontalScroll(page);
		await axeScan(page, 'reference-sheet');
	});

	test('the keyboard still fits on a 320dp phone', async ({ page }) => {
		// Thirteen white keys on the narrowest phone the app supports: the
		// outermost flanking keys must be fully on screen and still tappable.
		// The Android emulator once caught the last key hanging off the screen.
		await page.setViewportSize({ width: 320, height: 640 });
		await page.goto('/session');
		await expect(page.getByTestId('card-title')).toBeVisible();
		await noHorizontalScroll(page);

		const flanks = page.locator('[data-testid="keyboard"] [data-flank-pc]');
		await expect(flanks).toHaveCount(10);
		// Both white: the black keys are rendered after all thirteen whites, so
		// `flanks.last()` is an inset D♯ and would still fit if white E5 hung off
		// the right edge — which is the failure this test exists for.
		const first = (await flanks.first().boundingBox())!;
		const last = (await page
			.locator('[data-testid="keyboard"] [data-flank-pc="4"]')
			.boundingBox())!;
		for (const box of [first, last]) {
			expect(box.x).toBeGreaterThanOrEqual(0);
			expect(box.x + box.width).toBeLessThanOrEqual(320);
			expect(box.width).toBeGreaterThanOrEqual(12);
		}
		// The home octave stays tappable even here.
		const home = (await page
			.locator('[data-testid="keyboard"] [data-pc="0"]')
			.boundingBox())!;
		expect(home.width).toBeGreaterThanOrEqual(18);
	});

	test('session screen is thumb-usable on an iPhone', async ({ page }) => {
		await page.goto('/session');
		await expect(page.getByTestId('card-title')).toBeVisible();
		await noHorizontalScroll(page);
		await axeScan(page, 'session');

		const viewport = page.viewportSize()!;

		// Keys gave up the 44px width when the keyboard grew to an octave and a
		// half — narrow-but-tall is how a real piano deals with the same problem,
		// and the drag bubble names the key before the release commits it. What
		// still must hold: every key present, tappably wide, and 44px tall.
		for (const pc of [0, 2, 4, 5, 7, 9, 11]) {
			const box = await page.locator(`[data-testid="keyboard"] [data-pc="${pc}"]`).boundingBox();
			expect(box, `white key ${pc} missing`).not.toBeNull();
			expect(box!.width, `white key ${pc} width`).toBeGreaterThanOrEqual(22);
			expect(box!.height, `white key ${pc} height`).toBeGreaterThanOrEqual(MIN_TAP);
		}

		for (const pc of [1, 3, 6, 8, 10]) {
			const box = await page.locator(`[data-testid="keyboard"] [data-pc="${pc}"]`).boundingBox();
			expect(box, `black key ${pc} missing`).not.toBeNull();
			expect(box!.width, `black key ${pc} width`).toBeGreaterThanOrEqual(14);
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
