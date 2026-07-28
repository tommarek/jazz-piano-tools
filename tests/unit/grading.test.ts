import { describe, expect, it } from 'vitest';
import { Rating } from 'ts-fsrs';
import {
	AUTOMATIC_STREAK,
	FAMILIAR_STREAK,
	MEDIAN_WINDOW,
	deriveGrade,
	deriveMastery,
	median,
	rollingMedian
} from '../../src/lib/scheduler/grading';
import { TIME_TARGETS } from '../../src/lib/music/cards';

describe('median', () => {
	it('returns null for no data', () => {
		expect(median([])).toBeNull();
	});

	it('takes the middle of an odd sample and the mean of an even one', () => {
		expect(median([3, 1, 2])).toBe(2);
		expect(median([1, 2, 3, 4])).toBe(3);
	});

	it('rolls over only the most recent window', () => {
		const old = Array(MEDIAN_WINDOW).fill(10_000);
		const recent = Array(MEDIAN_WINDOW).fill(1000);
		expect(rollingMedian([...old, ...recent])).toBe(1000);
	});
});

describe('grade derivation', () => {
	const base = { cardType: 's2n' as const, medianMs: 2000 };

	it('grades a wrong answer Again regardless of speed', () => {
		expect(deriveGrade({ ...base, correct: false, responseMs: 200 })).toBe(Rating.Again);
	});

	it('grades a normal correct answer Good', () => {
		expect(deriveGrade({ ...base, correct: true, responseMs: 2000 })).toBe(Rating.Good);
	});

	it('grades slow-but-correct as Hard', () => {
		// This is the state the whole app exists to fix: right, but worked out.
		expect(deriveGrade({ ...base, correct: true, responseMs: 4001 })).toBe(Rating.Hard);
	});

	it('grades a fast answer Easy', () => {
		expect(deriveGrade({ ...base, correct: true, responseMs: 1199 })).toBe(Rating.Easy);
	});

	it('holds the boundaries exactly at the ratios', () => {
		expect(deriveGrade({ ...base, correct: true, responseMs: 4000 })).toBe(Rating.Good);
		expect(deriveGrade({ ...base, correct: true, responseMs: 1200 })).toBe(Rating.Good);
	});

	it('falls back to the card type baseline when there is no history', () => {
		const type = 'chain' as const;
		const { baseline } = TIME_TARGETS[type];
		expect(deriveGrade({ cardType: type, medianMs: null, correct: true, responseMs: baseline })).toBe(
			Rating.Good
		);
		expect(
			deriveGrade({ cardType: type, medianMs: null, correct: true, responseMs: baseline * 2 + 1 })
		).toBe(Rating.Hard);
	});

	it('judges a chain against a chain baseline, not a single-chord one', () => {
		// 9 seconds is fine for three chords and terrible for one.
		expect(deriveGrade({ cardType: 'chain', medianMs: null, correct: true, responseMs: 9000 })).toBe(
			Rating.Good
		);
		expect(deriveGrade({ cardType: 's2n', medianMs: null, correct: true, responseMs: 9000 })).toBe(
			Rating.Hard
		);
	});
});

describe('mastery thresholds', () => {
	it('needs a streak to leave new', () => {
		expect(
			deriveMastery({ consecutiveCorrect: FAMILIAR_STREAK - 1, medianMs: 500, cardType: 's2n' })
		).toBe('new');
		expect(
			deriveMastery({ consecutiveCorrect: FAMILIAR_STREAK, medianMs: 500, cardType: 's2n' })
		).toBe('familiar');
	});

	it('will not call a slow card automatic, however long the streak', () => {
		expect(
			deriveMastery({ consecutiveCorrect: 50, medianMs: 3000, cardType: 's2n' })
		).toBe('familiar');
	});

	it('needs both the streak and the time gate', () => {
		expect(
			deriveMastery({ consecutiveCorrect: AUTOMATIC_STREAK - 1, medianMs: 900, cardType: 's2n' })
		).toBe('familiar');
		expect(
			deriveMastery({ consecutiveCorrect: AUTOMATIC_STREAK, medianMs: 900, cardType: 's2n' })
		).toBe('automatic');
	});

	it('drops straight back to new when the streak breaks', () => {
		expect(deriveMastery({ consecutiveCorrect: 0, medianMs: 400, cardType: 's2n' })).toBe('new');
	});

	it('applies a per-chord equivalent target to chains', () => {
		// 5.5s over three chords is under 2s each; 6.5s is not.
		expect(deriveMastery({ consecutiveCorrect: 9, medianMs: 5500, cardType: 'chain' })).toBe(
			'automatic'
		);
		expect(deriveMastery({ consecutiveCorrect: 9, medianMs: 6500, cardType: 'chain' })).toBe(
			'familiar'
		);
	});

	it('never calls a card with no timing data automatic', () => {
		expect(deriveMastery({ consecutiveCorrect: 20, medianMs: null, cardType: 's2n' })).toBe(
			'familiar'
		);
	});
});
