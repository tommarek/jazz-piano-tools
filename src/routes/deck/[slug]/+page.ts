import { error, redirect } from '@sveltejs/kit';
import { deckCards } from '$lib/data/browse';
import { deckLabel, deckSection, deckSlug, parseDeckSlug } from '$lib/data/decks';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ params }) => {
	const deck = parseDeckSlug(params.slug);
	// 'all' is a deck slug from before the split, not an unknown one: it names
	// the theory section, whose canonical slug is now 'theory'. Sent to the
	// canonical URL rather than 404'd, so a link that still starts a session
	// still browses one too.
	if (params.slug === 'all') redirect(307, '/deck/theory');
	// parseDeckSlug falls back to the theory section on anything it does not
	// know, which is right for a session — start something rather than fail —
	// but wrong here: a browser showing a different deck than the URL named
	// would be lying about what you are looking at.
	if (deckSlug(deck) !== params.slug) error(404, `No deck called "${params.slug}"`);

	const browse = await deckCards(deck);
	return {
		deck,
		slug: deckSlug(deck),
		label: deckLabel(deck),
		section: deckSection(deck),
		browse
	};
};
