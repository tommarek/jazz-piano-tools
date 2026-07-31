import { describe, expect, it } from 'vitest';
import { TOPICS, TOPICS_BY_ID } from '../../src/lib/content/reference';
import { CARD_TYPES, buildCatalogue, renderCard } from '../../src/lib/music/cards';

const catalogue = buildCatalogue();

describe('reference topics', () => {
	it('number the eleven the README claims', () => {
		// The count is quoted in prose nothing else checks, so it silently drifted
		// when the ear topic arrived.
		expect(TOPICS.length).toBe(11);
	});

	it('have unique ids', () => {
		expect(new Set(TOPICS.map((t) => t.id)).size).toBe(TOPICS.length);
	});

	it('have a title, a blurb and some content', () => {
		for (const topic of TOPICS) {
			expect(topic.title.length).toBeGreaterThan(0);
			expect(topic.blurb.length).toBeGreaterThan(0);
			expect(topic.sections.length).toBeGreaterThan(0);
			for (const section of topic.sections) {
				const hasContent = !!(section.body?.length || section.list?.length || section.table);
				expect(hasContent, `${topic.id} has an empty section`).toBe(true);
			}
		}
	});

	it('only link to topics that exist', () => {
		for (const topic of TOPICS) {
			for (const id of topic.related) {
				expect(TOPICS_BY_ID[id], `${topic.id} links to missing ${id}`).toBeDefined();
			}
			expect(topic.related).not.toContain(topic.id);
		}
	});

	it('give every table the same number of cells in every row', () => {
		for (const topic of TOPICS) {
			for (const section of topic.sections) {
				if (!section.table) continue;
				for (const row of section.table.rows) {
					expect(row.length, `${topic.id} table row width`).toBe(section.table.head.length);
				}
			}
		}
	});
});

describe('every card can explain itself', () => {
	it('sends minor chains to the minor topic and major ones to voice leading', () => {
		const minor = catalogue.find((c) => c.type === 'chain' && c.mode === 'minor')!;
		const major = catalogue.find((c) => c.type === 'chain' && c.mode === 'major')!;
		expect(renderCard(minor).topic).toBe('minor-two-five');
		expect(renderCard(major).topic).toBe('guide-tones');
	});

	it('renders every card type, and every topic it names resolves', () => {
		// Asserted against renderCard's actual topic field — the mapping the app
		// reads when you ask "why" — and over every type, so a drill added without
		// a topic is caught here rather than by an empty reference panel.
		const seen = new Set<string>();
		for (const spec of catalogue) {
			const topic = renderCard(spec).topic;
			expect(TOPICS_BY_ID[topic], `no topic '${topic}' for ${spec.id}`).toBeDefined();
			seen.add(spec.type);
		}
		expect([...seen].sort()).toEqual([...CARD_TYPES].sort());
	});

	it('covers every topic with at least one card, or is reachable by browsing', () => {
		const used = new Set(catalogue.map((spec) => renderCard(spec).topic));
		const unused = TOPICS.map((t) => t.id).filter((id) => !used.has(id));
		// 'scheduling' is background reading with no drill of its own; the
		// symbol table in 'qualities' is what the ear and spelling topics send you
		// to; and 'shells' became reading when the root-shell drills were cut —
		// the concept is still worth explaining, nothing drills it. Everything
		// else must be reachable from a card.
		expect(unused.sort()).toEqual(['qualities', 'scheduling', 'shells']);
		for (const id of unused) {
			const linked = TOPICS.some((t) => t.related.includes(id));
			expect(linked || id === 'scheduling', `${id} is unreachable`).toBe(true);
		}
	});
});
