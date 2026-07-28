import { error } from '@sveltejs/kit';
import { TOPICS_BY_ID } from '$lib/content/reference';
import type { PageLoad } from './$types';

// A universal load, so a topic opened offline renders from the cached bundle
// rather than needing the server.
export const load: PageLoad = async ({ params }) => {
	const topic = TOPICS_BY_ID[params.id];
	if (!topic) error(404, 'No such topic');
	return { topic };
};
