/**
 * Exploratory walkthrough. Drives every screen and flow, screenshots each state,
 * and records console errors, page errors, failed requests and horizontal
 * overflow as it goes. Not a test suite — a harness for looking at the thing.
 *
 *   npx vite-node explore/drive.mjs
 */
import { chromium, devices } from '@playwright/test';
import { mkdirSync, writeFileSync } from 'node:fs';
import { parseCardId, renderCard } from '../src/lib/music/cards.ts';

const BASE = 'http://127.0.0.1:4173';
const OUT = '/tmp/vt-explore';
mkdirSync(OUT, { recursive: true });

const findings = [];
let shotIndex = 0;

const browser = await chromium.launch();
const context = await browser.newContext({
	...devices['iPhone 14 Pro'],
	defaultBrowserType: 'chromium'
});
const page = await context.newPage();

page.on('console', (m) => {
	if (m.type() === 'error') findings.push({ kind: 'console', text: m.text() });
});
page.on('pageerror', (e) => findings.push({ kind: 'pageerror', text: e.message }));
page.on('requestfailed', (r) => {
	const url = r.url();
	if (!url.startsWith(BASE)) return;
	findings.push({ kind: 'requestfailed', text: `${url} — ${r.failure()?.errorText}` });
});
page.on('response', (r) => {
	if (r.url().startsWith(BASE) && r.status() >= 500) {
		findings.push({ kind: 'http', text: `${r.status()} ${r.url()}` });
	}
});

async function reset(settings = {}) {
	const res = await page.request.post(`${BASE}/api/test/reset`, { data: { settings } });
	if (!res.ok()) throw new Error(`reset failed ${res.status()}`);
}

async function shot(name, opts = {}) {
	shotIndex += 1;
	const file = `${OUT}/${String(shotIndex).padStart(2, '0')}-${name}.png`;
	await page.screenshot({ path: file, fullPage: !!opts.full });
	const overflow = await page.evaluate(
		() => document.documentElement.scrollWidth - document.documentElement.clientWidth
	);
	if (overflow > 1) {
		findings.push({ kind: 'overflow', text: `${name}: ${overflow}px horizontal overflow` });
	}
	return file;
}

async function cardId() {
	const id = await page.locator('[data-card-id]').getAttribute('data-card-id');
	if (!id) throw new Error('no card on screen');
	return id;
}

async function currentCard() {
	return renderCard(parseCardId(await cardId()));
}

async function answer(card, correct = true) {
	if (card.input === 'shell-name') {
		await page.getByTestId(`root-${correct ? card.expectedShell.root : 'C'}`).click();
		await page
			.getByTestId(`guide-${correct ? card.expectedShell.guide : 'M3'}`)
			.click();
	} else if (card.input === 'chord-name') {
		const { CHORD_ROOTS } = await import('../src/lib/music/voicings.ts');
		const { parseNote, pitchClass } = await import('../src/lib/music/theory.ts');
		const onGrid = CHORD_ROOTS.find((r) => pitchClass(parseNote(r, 4)) === card.expectedChord.rootPc);
		await page.getByTestId(`root-${correct ? onGrid : 'C'}`).click();
		await page.getByTestId(`quality-${correct ? card.expectedChord.quality : 'dim7'}`).click();
	} else if (card.input === 'mode-name') {
		await page.getByTestId(`mode-${correct ? card.expectedMode : 'Locrian'}`).click();
	} else {
		for (let s = 0; s < card.steps.length; s++) {
			if (card.steps.length > 1) await page.getByTestId(`step-${s}`).click();
			const pcs = correct
				? card.steps[s].expected
				: card.steps[s].expected.map((pc) => (pc + 1) % 12);
			for (const pc of pcs) {
				await page.locator(`[data-testid="keyboard"] [data-pc="${pc}"]`).click();
			}
		}
	}
	await page.getByTestId('check-answer').click();
	await page.waitForTimeout(150);
}

function note(text) {
	findings.push({ kind: 'note', text });
}

// ---------------------------------------------------------------------------
// 1. Stats screens against seeded history
// ---------------------------------------------------------------------------
await page.goto(`${BASE}/`);
await page.waitForTimeout(400);
await shot('today-with-history');

const headline = await page.getByTestId('headline-metric').textContent();
const due = await page.getByTestId('due-count').textContent();
const doneToday = await page.getByTestId('today-count').textContent();
note(`Today: headline ${headline}s/chord, ${due} queued, ${doneToday} done today`);

await page.goto(`${BASE}/progress`);
await page.waitForTimeout(500);
await shot('progress-top');
await shot('progress-full', { full: true });

// Chart hover — the crosshair and tooltip.
const chart = page.locator('svg[role="img"]').first();
const box = await chart.boundingBox();
await page.mouse.move(box.x + box.width * 0.55, box.y + box.height * 0.5);
await page.waitForTimeout(250);
await shot('progress-chart-hover');

await page.getByRole('button', { name: /table view/i }).click();
await page.waitForTimeout(300);
await shot('progress-table', { full: true });

// ---------------------------------------------------------------------------
// 2. Every drill type, right and wrong
// ---------------------------------------------------------------------------
const DRILLS = [
	['s2n', {}],
	['n2s', {}],
	['chain', {}],
	['vl', {}],
	['ext', {}],
	['dia', {}],
	['ivl', {}],
	['mode', {}],
	['rootless', { rootlessUnlocked: true }]
];

for (const [type, extra] of DRILLS) {
	await reset({ activeCardTypes: [type], newCardsPerDay: 6, sessionCardCap: 6, ...extra });
	await page.goto(`${BASE}/session`);
	await page.waitForTimeout(300);
	await shot(`drill-${type}-prompt`);

	const card = await currentCard();
	note(`${type}: "${card.title}" / "${card.instruction}"`);

	await answer(card, false);
	await shot(`drill-${type}-wrong`);
	const feedbackWrong = await page.getByTestId('feedback').getAttribute('data-correct');
	if (feedbackWrong !== 'false') findings.push({ kind: 'bug', text: `${type}: wrong answer not marked incorrect` });

	await page.getByTestId('next-card').click();
	await page.waitForTimeout(200);
	const card2 = await currentCard();
	await answer(card2, true);
	await shot(`drill-${type}-right`);
	const feedbackRight = await page.getByTestId('feedback').getAttribute('data-correct');
	if (feedbackRight !== 'true') findings.push({ kind: 'bug', text: `${type}: correct answer not marked correct` });
}

// ---------------------------------------------------------------------------
// 3. Chain partial-answer behaviour
// ---------------------------------------------------------------------------
await reset({ activeCardTypes: ['chain'], newCardsPerDay: 5 });
await page.goto(`${BASE}/session`);
await page.waitForTimeout(300);
const chainCard = await currentCard();
const checkDisabledEmpty = await page.getByTestId('check-answer').isDisabled();
for (const pc of chainCard.steps[0].expected) {
	await page.locator(`[data-testid="keyboard"] [data-pc="${pc}"]`).click();
}
await page.waitForTimeout(200);
await shot('chain-one-chord-in');
const checkDisabledPartial = await page.getByTestId('check-answer').isDisabled();
note(`chain: check disabled with 0 chords = ${checkDisabledEmpty}, with 1 of 3 = ${checkDisabledPartial}`);
if (!checkDisabledPartial) findings.push({ kind: 'bug', text: 'chain accepts a partial answer' });

// ---------------------------------------------------------------------------
// 4. "No idea" and the reference sheet
// ---------------------------------------------------------------------------
await reset({ activeCardTypes: ['rootless'], newCardsPerDay: 5, rootlessUnlocked: true });
await page.goto(`${BASE}/session`);
await page.waitForTimeout(300);
await page.getByTestId('give-up').click();
await page.waitForTimeout(250);
await shot('no-idea-reveal');
await page.getByTestId('explain').click();
await page.waitForTimeout(400);
await shot('reference-sheet-rootless');
await page.keyboard.press('Escape');
await page.waitForTimeout(300);
const stillOnCard = await page.getByTestId('card-title').isVisible();
note(`reference sheet: session survived Escape = ${stillOnCard}`);

// ---------------------------------------------------------------------------
// 5. Reference section
// ---------------------------------------------------------------------------
await page.goto(`${BASE}/reference`);
await page.waitForTimeout(300);
await shot('reference-index', { full: true });
for (const id of ['guide-tones', 'minor-two-five', 'extensions', 'scheduling']) {
	await page.goto(`${BASE}/reference/${id}`);
	await page.waitForTimeout(250);
	await shot(`reference-${id}`, { full: true });
}

// ---------------------------------------------------------------------------
// 6. Settings round-trip
// ---------------------------------------------------------------------------
await reset({});
await page.goto(`${BASE}/settings`);
await page.waitForTimeout(300);
await shot('settings-top', { full: true });

await page.locator('input[name="sessionMinutes"]').fill('9');
await page.locator('input[name="newCardsPerDay"]').fill('3');
await page.locator('input[name="visualiseDelayMs"]').fill('1500');
await page.locator('input[name="cardTypes"][value="ivl"]').uncheck();
await page.getByTestId('save-settings').click();
await page.waitForTimeout(500);
await shot('settings-saved');
const savedMinutes = await page.locator('input[name="sessionMinutes"]').inputValue();
const ivlChecked = await page.locator('input[name="cardTypes"][value="ivl"]').isChecked();
note(`settings: sessionMinutes persisted as ${savedMinutes}, intervals unchecked = ${!ivlChecked}`);

// Visualise delay should now blank the keyboard.
await page.goto(`${BASE}/session`);
await page.waitForTimeout(200);
await shot('visualise-blanked');
const blanked = await page.getByTestId('keyboard').getAttribute('data-blanked');
note(`visualise: keyboard blanked on entry = ${blanked}`);
await page.waitForTimeout(1800);
const unblanked = await page.getByTestId('keyboard').getAttribute('data-blanked');
note(`visualise: keyboard revealed after delay = ${unblanked === 'false'}`);
await shot('visualise-revealed');

// Guard against the settings form dropping unrelated values.
await page.goto(`${BASE}/settings`);
await page.waitForTimeout(300);
const stillOff = await page.locator('input[name="cardTypes"][value="ivl"]').isChecked();
if (stillOff) findings.push({ kind: 'bug', text: 'settings: unchecked drill type came back on' });

// ---------------------------------------------------------------------------
// 7. Session summary + empty state
// ---------------------------------------------------------------------------
await reset({ activeCardTypes: ['s2n'], newCardsPerDay: 3, sessionCardCap: 3 });
await page.goto(`${BASE}/session`);
await page.waitForTimeout(300);
for (let i = 0; i < 3; i++) {
	const c = await currentCard();
	await answer(c, i !== 1);
	await page.getByTestId('next-card').click();
	await page.waitForTimeout(200);
	if (!(await page.getByTestId('card-title').isVisible())) break;
}
await page.getByTestId('end-session').click();
await page.waitForTimeout(300);
await shot('session-summary');

await reset({ activeCardTypes: ['s2n'], newCardsPerDay: 0 });
await page.goto(`${BASE}/`);
await page.waitForTimeout(300);
await shot('today-nothing-due');
const startDisabled = await page.getByTestId('start-session').getAttribute('aria-disabled');
note(`empty state: Start disabled = ${startDisabled}`);

// ---------------------------------------------------------------------------
// 8. Speed round
// ---------------------------------------------------------------------------
await page.goto(`${BASE}/session?mode=speed`);
await page.waitForTimeout(400);
await shot('speed-round');

// ---------------------------------------------------------------------------
// 9. The gate, before and after
// ---------------------------------------------------------------------------
await reset({});
await page.goto(`${BASE}/`);
await page.waitForTimeout(300);
await shot('gate-locked');

writeFileSync(`${OUT}/findings.json`, JSON.stringify(findings, null, 2));
console.log(JSON.stringify(findings, null, 2));
await browser.close();
