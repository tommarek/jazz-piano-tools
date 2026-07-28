import { buildQueue, type SessionMode } from '$lib/data/queue';
import { getSettings } from '$lib/data/settings';
import { startSession } from '$lib/data/review';
import type { PageLoad } from './$types';

const MODES: SessionMode[] = ['srs', 'speed', 'visualise'];

export const load: PageLoad = async ({ url }) => {
	const param = url.searchParams.get('mode') ?? 'srs';
	const mode = (MODES.includes(param as SessionMode) ? param : 'srs') as SessionMode;
	const settings = await getSettings();
	const queue = await buildQueue({ mode, settings });
	const sessionId = crypto.randomUUID();
	await startSession(sessionId, mode);
	return { sessionId, mode, queue, settings };
};
