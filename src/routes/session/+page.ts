import { buildQueue, deckCounts, type SessionMode } from '$lib/data/queue';
import {
	deckEmptyReason,
	deckLabel,
	deckSection,
	deckSlug,
	liveDeckTypes,
	parseDeckSlug
} from '$lib/data/decks';
import { getSettings } from '$lib/data/settings';
import { startSession } from '$lib/data/review';
import type { PageLoad } from './$types';

const MODES: SessionMode[] = ['srs', 'speed', 'visualise'];

export const load: PageLoad = async ({ url }) => {
	const param = url.searchParams.get('mode') ?? 'srs';
	const mode = (MODES.includes(param as SessionMode) ? param : 'srs') as SessionMode;
	// A deck narrows the session to one part of the catalogue; no deck is the
	// mixed queue, and that is still the default everywhere.
	const deck = parseDeckSlug(url.searchParams.get('deck'));
	const settings = await getSettings();
	const queue = await buildQueue({ mode, settings, deck });
	// For the switcher on the summary. The nav is hidden while drilling, so
	// without this the only way to change deck is to finish, go home, and find
	// the picker again — three taps to answer "what next", asked every session.
	const decks = await deckCounts(deckSection(deck));
	const sessionId = crypto.randomUUID();
	await startSession(sessionId, mode);
	// The theory section is the app's default and needs no badge; everything
	// else — a drill, a stage, the whole ear section — is worth naming, because
	// a narrowed session otherwise looks like a run of similar cards.
	const showDeck = deck.kind !== 'section' || deckSection(deck) === 'ear';
	// "Nothing due" is a lie when the deck has no card to deal at all: an ear
	// deck with the sound off never had one, and telling someone to come back
	// tomorrow leaves them waiting on a switch instead of flipping it.
	const emptyBlock =
		liveDeckTypes(deck, settings).length === 0 ? deckEmptyReason(deck, settings) : null;
	return {
		sessionId,
		mode,
		queue,
		settings,
		deck,
		deckSlug: deckSlug(deck),
		decks,
		deckLabel: deckLabel(deck),
		section: deckSection(deck),
		showDeck,
		emptyBlock
	};
};
