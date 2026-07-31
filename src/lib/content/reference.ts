/**
 * The reference layer.
 *
 * Drills tell you *that* you were wrong; this tells you *why*. It is reachable
 * from a card only after the answer is revealed — looking something up mid-
 * attempt would turn a retrieval test into a reading exercise, which is the one
 * thing the whole app is built to avoid. Outside a session it browses freely.
 *
 * Content is structured data rather than markdown so it renders identically in
 * the in-session sheet and on the reference page, with no parser to ship.
 */

import {
	EAR_GATE_ACCURACY,
	EAR_MIN_SAMPLE,
	GATE_MIN_SAMPLE,
	GATE_PER_CHORD_MS
} from '$lib/data/stages';
import { CARD_TYPE_LABEL, stagesOf, TIME_TARGETS, type Section } from '$lib/music/cards';
import { AUTOMATIC_STREAK, EASY_RATIO, FAMILIAR_STREAK, HARD_RATIO } from '$lib/scheduler/grading';
import { MAX_DAYS_BEFORE_AUTOMATIC } from '$lib/scheduler/fsrs';


export interface ReferenceSection {
	heading?: string;
	body?: string[];
	list?: string[];
	table?: { head: string[]; rows: string[][] };
}

export interface ReferenceTopic {
	id: string;
	title: string;
	/** One line, shown on the index and as the sheet's subtitle. */
	blurb: string;
	sections: ReferenceSection[];
	related: string[];
}

/**
 * What each stage opens, read off the ladders rather than written out. A
 * hand-kept list went stale the moment the ear decks were added, and the one
 * place the path is explained is the worst place to be wrong about it — which
 * is also why both sections are listed: a reader shown only the theory ladder
 * is told the app's path is three stages when half their deck is on another.
 */
const STAGE_GATE: Record<Section, Record<number, string>> = {
	theory: {
		1: 'Open from the start.',
		2: 'Opens once every key has an automatic guide-tone pair.',
		3: `Opens once ${GATE_MIN_SAMPLE} correct chains run under ${GATE_PER_CHORD_MS / 1000} seconds per chord, with every key at least half automatic on guide tones.`
	},
	ear: {
		1: 'Open from the start.',
		2: `Opens at ${Math.round(EAR_GATE_ACCURACY * 100)}% correct on heard intervals over ${EAR_MIN_SAMPLE} attempts — accuracy, not speed: perception stays slow long after it is reliable.`
	}
};

const pathList = (section: Section) =>
	stagesOf(section).map((stage) => {
		const drills = stage.types
			.map((t) => CARD_TYPE_LABEL[t])
			.map((label) => label.charAt(0).toLowerCase() + label.slice(1))
			.join(', ');
		return `Stage ${stage.n} — ${stage.title}: ${drills}. ${STAGE_GATE[section][stage.n]}`;
	});

export const TOPICS: ReferenceTopic[] = [
	{
		id: 'shells',
		title: 'Shell voicings',
		blurb: 'Two notes that carry a chord: the root and one guide tone.',
		sections: [
			{
				body: [
					'A shell is the root plus either the 3rd or the 7th. Two notes, left hand, nothing else. It works because those are the only two notes that decide what kind of chord you are hearing.',
					'The 5th tells you almost nothing — it is the same in a major 7th, a minor 7th and a dominant. Drop it. The root anchors the harmony and the guide tone names it.',
					'You may have seen 3rd + 7th together called a shell elsewhere. Here that pair is a guide-tone voicing, and it is what this app drills: the root belongs to the bass player. A shell keeps the root because the word comes from solo and duo playing, where nobody else is covering it.'
				]
			},
			{
				heading: 'The two shells',
				table: {
					head: ['Shell', 'Notes', 'Cmaj7', 'Cm7', 'C7'],
					rows: [
						['root–3', 'root + 3rd', 'C + E', 'C + E♭', 'C + E'],
						['root–7', 'root + 7th', 'C + B', 'C + B♭', 'C + B♭']
					]
				}
			},
			{
				body: [
					'Notice that root–3 cannot tell Cmaj7 from C7, and root–7 cannot tell Cm7 from C7. Each shell answers half the question — two notes genuinely do not determine one chord. The same holds for the 3–7 pair, which is why the guide-tone naming drill accepts every quality its pair fits.'
				]
			},
			{
				heading: 'Why bother',
				body: [
					'Shells are what you play under a melody when you are sight-reading, comping behind a singer, or thinking about anything other than your left hand. They are also the skeleton every fuller voicing hangs on — learn the shell and the rootless voicing is one step away.'
				]
			}
		],
		related: ['guide-tones', 'qualities', 'rootless']
	},

	{
		id: 'guide-tones',
		title: 'Guide tones and voice leading',
		blurb: 'Why only one note moves in a ii–V–I.',
		sections: [
			{
				body: [
					'The 3rd and the 7th are the guide tones. Across a ii–V–I they barely move — and that is the point. Play the chain with the guide tone on top and your hand almost stays still.'
				]
			},
			{
				heading: 'In C major',
				table: {
					head: ['', 'Dm7', 'G7', 'Cmaj7'],
					rows: [
						['7–3–7', 'C (7th)', 'B (3rd)', 'B (7th)'],
						['3–7–3', 'F (3rd)', 'F (7th)', 'E (3rd)']
					]
				}
			},
			{
				body: [
					'In the first row the 7th of Dm7 falls a semitone to the 3rd of G7, which is then simply held as the 7th of Cmaj7. In the second the 3rd of Dm7 is held as the 7th of G7, which falls a semitone to the 3rd of Cmaj7.',
					'Either way: one note falls a semitone, one note holds. That is the whole mechanism, and it is the same in all twelve keys.'
				]
			},
			{
				heading: 'Why it alternates',
				body: [
					'The 7th of one chord becomes the 3rd of the next because the roots move down a fifth. Each step swaps which guide tone is on top, so the two chains — 7–3–7 and 3–7–3 — are the only two shapes there are.',
					'Played together as a two-note voicing — no root, a bassist has it — the pair fixes surprisingly little: F and C are the 3–7 of D♭maj7 and the ♭3–♭7 of Dm7 alike. That is why the guide-tone naming drill accepts every chord the pair fits.'
				]
			}
		],
		related: ['shells', 'minor-two-five', 'rootless']
	},

	{
		id: 'minor-two-five',
		title: 'The minor ii–V–i',
		blurb: 'Half-diminished ii, a dominant V, and a tonic that is not m7.',
		sections: [
			{
				body: [
					'A minor ii–V–i is iiø7 – V7 – i. The ii comes from the natural minor, so its 5th is flat: in C minor that is Dm7♭5, not Dm7.',
					'The V is a real dominant with a major 3rd. It has to be — that note is the leading tone. In C minor the V is G7 with a B natural, borrowed from the harmonic minor. A Gm7 there would not resolve.'
				]
			},
			{
				heading: 'C minor',
				table: {
					head: ['', 'Dm7♭5', 'G7', 'Cm(maj7)'],
					rows: [
						['7–3–7', 'C (7th)', 'B (3rd)', 'B (7th)'],
						['3–7–3', 'F (3rd)', 'F (7th)', 'E♭ (3rd)']
					]
				}
			},
			{
				body: [
					'The 7–3–7 chain behaves exactly as it does in major. The 3–7–3 chain has one difference worth feeling: the 7th of V falls a whole tone — not a semitone — to the 3rd of a minor tonic. F to E♭, not F to E.'
				]
			},
			{
				heading: 'Which minor tonic',
				body: [
					'This app uses m(maj7) — root, ♭3, 5, natural 7. It is the characteristic minor-tonic sound, and unlike m6 it actually has a 7th — and a guide-tone voicing is the 3rd and the 7th. In practice i m7, i m6 and i m(maj7) are all played; m(maj7) is the one that teaches the guide tone.'
				]
			}
		],
		related: ['guide-tones', 'qualities']
	},

	{
		id: 'rootless',
		title: 'Rootless A and B forms',
		blurb: 'Four notes, no root, two inversions — and why the order matters.',
		sections: [
			{
				body: [
					'Once a bass player is covering the root you can drop it and use the hand for something more useful: the 3rd, the 7th, and the colour notes. That is a rootless voicing.',
					'There are two, and they are the same four notes in a different order. The A form puts the 3rd on the bottom; the B form takes the A form\'s top two voices and moves them underneath, which puts the 7th on the bottom.'
				]
			},
			{
				heading: 'The stacks, bottom-up',
				table: {
					head: ['Quality', 'A form', 'B form'],
					rows: [
						['maj7', '3–5–7–9', '7–9–3–5'],
						['m7', '♭3–5–♭7–9', '♭7–9–♭3–5'],
						['7', '3–13–♭7–9', '♭7–9–3–13'],
						['m7♭5', '♭3–♭5–♭7–1', '♭7–1–♭3–♭5']
					]
				}
			},
			{
				body: [
					'Dominants take the 13th rather than the 5th. On a V chord the 5th adds nothing and the 13th is what everyone actually plays.',
					'Dm7 A form is F–A–C–E. Dm7 B form is C–E–F–A. Same notes, and that is why this drill asks you to tap them bottom-up: your answer is graded by pitch class, so the order is the only thing that distinguishes the two forms.'
				]
			},
			{
				heading: 'When you use which',
				body: [
					'Alternate them so your hand stays in one place. Through a ii–V–I: if the ii is an A form, make the V a B form and the I an A form again. Roots move down a fifth, so alternating keeps every voice within a step or two of where it was.',
					'Keep the whole thing between roughly C3 and C5. Lower than that and four notes turn to mud.'
				]
			}
		],
		related: ['shells', 'extensions', 'guide-tones']
	},

	{
		id: 'qualities',
		title: 'Chord qualities and symbols',
		blurb: 'What each symbol means, in scale degrees.',
		sections: [
			{
				table: {
					head: ['Symbol', 'Degrees', 'On C'],
					rows: [
						['maj7', '1 3 5 7', 'C E G B'],
						['m7', '1 ♭3 5 ♭7', 'C E♭ G B♭'],
						['7', '1 3 5 ♭7', 'C E G B♭'],
						['m7♭5', '1 ♭3 ♭5 ♭7', 'C E♭ G♭ B♭'],
						['°7', '1 ♭3 ♭5 ♭♭7', 'C E♭ G♭ B♭♭'],
						['m(maj7)', '1 ♭3 5 7', 'C E♭ G B']
					]
				}
			},
			{
				body: [
					'The 7th is what separates most of these. maj7 and m(maj7) keep the natural 7th; m7, 7 and m7♭5 flat it; the diminished 7th flats it twice — which sounds like a 6th but is spelled as a 7th, because a chord built in thirds must have one of each letter.',
					'm7♭5 is also written ø7 and called half-diminished. It is a m7 with the 5th lowered, and it is the ii of every minor key.'
				]
			},
			{
				heading: 'Reading them fast',
				list: [
					'A lower-case m or a minus sign lowers the 3rd.',
					'A bare number — C7 — means a dominant: major 3rd, flat 7th.',
					'"maj" or a triangle applies to the 7th, not the chord: Cmaj7 and Cm(maj7) both have a natural B.',
					'° means fully diminished; ø means half.'
				]
			}
		],
		related: ['shells', 'extensions', 'diatonic']
	},

	{
		id: 'extensions',
		title: 'Extensions and alterations',
		blurb: '9ths, 11ths, 13ths — and which ones a chord will take.',
		sections: [
			{
				body: [
					'Keep stacking thirds past the 7th and you get the 9th, 11th and 13th. They are the same pitch classes as the 2nd, 4th and 6th, but they are named as extensions because they sit above the 7th and behave like colour rather than structure.'
				]
			},
			{
				heading: 'What goes on what',
				table: {
					head: ['Quality', 'Usually takes', 'Avoid'],
					rows: [
						['maj7', '9, ♯11, 13', '11 (clashes with the 3rd)'],
						['m7', '9, 11, 13', '—'],
						['7', '9, ♭9, ♯9, ♯11, 13, ♭13', '11 natural'],
						['m7♭5', '11, ♭13', '♭9 (a minor 9th against the root)'],
						['°7', '—', 'most things']
					]
				}
			},
			{
				body: [
					'The dominant takes everything, which is why the alterations are drilled there. ♭9 and ♯9 both work over a V going to a minor tonic; ♯11 and ♭13 are the ones that make a dominant sound like it is leaning somewhere.',
					'A natural 11 on a maj7 or a dominant sits a semitone above the 3rd and fights it. That is the one to leave alone unless you mean it.'
				]
			},
			{
				heading: 'Counting them',
				body: [
					'The 9th is an octave above the 2nd, the 11th above the 4th, the 13th above the 6th. So the 13th of C is A, and the ♭13 is A♭. Count the letter first, then adjust: the ♯9 of A is B♯, not C, because it has to be some kind of B.'
				]
			}
		],
		related: ['rootless', 'qualities', 'spelling']
	},

	{
		id: 'diatonic',
		title: 'Diatonic harmony',
		blurb: 'The seven chords in a major key, and why they are those seven.',
		sections: [
			{
				body: [
					'Build a four-note chord on each degree of a major scale using only notes from that scale, and you get the same pattern of qualities in every key. Learn the pattern once and it transposes for free.'
				]
			},
			{
				table: {
					head: ['Degree', 'Quality', 'In C', 'In D♭'],
					rows: [
						['I', 'maj7', 'Cmaj7', 'D♭maj7'],
						['ii', 'm7', 'Dm7', 'E♭m7'],
						['iii', 'm7', 'Em7', 'Fm7'],
						['IV', 'maj7', 'Fmaj7', 'G♭maj7'],
						['V', '7', 'G7', 'A♭7'],
						['vi', 'm7', 'Am7', 'B♭m7'],
						['vii', 'm7♭5', 'Bm7♭5', 'Cm7♭5']
					]
				}
			},
			{
				body: [
					'Only one chord in the key is a dominant — the V. That is what makes it the V: it is the only place a tritone appears between the 3rd and the 7th, and that tritone is what wants to resolve.',
					'ii–V–I is the first three of these you will ever need. iii and vi are the substitutes that let a progression drift.'
				]
			},
			{
				heading: 'Spelling traps',
				body: [
					'The IV of G♭ is C♭, not B. The vii of B is A♯, not B♭. The key signature decides the letter — you cannot have two chords on the same letter in one key. The app grades you on the sound, so tapping B is accepted, but it will show you the right spelling.'
				]
			}
		],
		related: ['modes', 'qualities', 'spelling']
	},

	{
		id: 'modes',
		title: 'Scales and modes',
		blurb: 'The same seven notes, starting somewhere else.',
		sections: [
			{
				body: [
					'A mode is a major scale played from a different degree. All seven modes of C major use exactly the notes of C major — what changes is which note is home, and therefore which intervals you hear against it.',
					'Practically: find the key the chord belongs to, then play that key\'s scale starting on the chord\'s root.'
				]
			},
			{
				table: {
					head: ['Degree', 'Mode', 'Sounds like', 'Over'],
					rows: [
						['I', 'Ionian', 'the major scale', 'maj7'],
						['ii', 'Dorian', 'minor with a natural 6th', 'm7'],
						['iii', 'Phrygian', 'minor with a ♭2', 'm7'],
						['IV', 'Lydian', 'major with a ♯4', 'maj7'],
						['V', 'Mixolydian', 'major with a ♭7', '7'],
						['vi', 'Aeolian', 'the natural minor', 'm7'],
						['vii', 'Locrian', 'minor with a ♭2 and ♭5', 'm7♭5']
					]
				}
			},
			{
				body: [
					'So Am7 in G major takes A Dorian: the notes of G major from A. The same Am7 in C major takes A Aeolian. The chord did not change; the context did — which is exactly why this is drilled as "chord in key" rather than "chord".'
				]
			},
			{
				heading: 'The one note that matters',
				body: [
					'Each mode is defined by a single note against its parallel major or minor. Dorian is the natural 6th. Lydian is the ♯4. Mixolydian is the ♭7. If you can hear that one note you can name the mode without counting.'
				]
			}
		],
		related: ['diatonic', 'extensions']
	},

	{
		id: 'spelling',
		title: 'Note spelling and intervals',
		blurb: 'Why the app writes B♭♭ when you tapped an A.',
		sections: [
			{
				body: [
					'An interval has two parts: a letter distance and a semitone distance. A third is always some kind of third — it always spans two letters — and the accidental decides which kind. That is why D♭ and C♯ are different notes even though they sound identical.'
				]
			},
			{
				table: {
					head: ['Interval', 'Built as', 'From C', 'Not'],
					rows: [
						['minor 3rd', '2 letters, 3 semitones', 'E♭', 'D♯'],
						['diminished 5th', '4 letters, 6 semitones', 'G♭', 'F♯'],
						['diminished 7th', '6 letters, 9 semitones', 'B♭♭', 'A'],
						['sharp 9th', '8 letters, 15 semitones', 'D♯', 'E♭']
					]
				}
			},
			{
				body: [
					'C°7 really is C–E♭–G♭–B♭♭. It sounds like an A on top and you play the A key, but writing it as A would give the chord two G-ish letters and no B, which stops it being a stack of thirds.',
					'This app grades you on the sound — pitch class — so the right key is always accepted. The spelling is shown afterwards because reading it is a separate skill worth having.'
				]
			},
			{
				heading: 'Sharp side, flat side',
				body: [
					'Chord roots here are written the way lead sheets write them: F♯m7 and F♯7, but D♭maj7 rather than C♯maj7. Major keys use G♭; minor keys use C♯ and A♭. There is no deep rule — it is what needs fewer accidentals in that context.'
				]
			}
		],
		related: ['qualities', 'extensions', 'diatonic']
	},

	{
		id: 'ear',
		title: 'Training the ear',
		blurb: 'Why the drill hides the notes, and why replaying is not cheating.',
		sections: [
			{
				body: [
					'Everything else in this app is read: you see a symbol and produce notes. The ear drills run the other way, and they are the half that decides whether any of it is music. Naming a chord you are looking at is a lookup; naming one you can only hear is recognition.',
					'Two of them. The interval drill plays two notes and asks how far apart they are. The quality drill plays one chord and asks what kind it is — which is the 3rd and the 7th again, heard rather than spelled.'
				]
			},
			{
				heading: 'Why you are never told the starting note',
				body: [
					'An interval is a distance, not a pair of notes. A perfect 5th from D♭ has to sound like a perfect 5th from G, or what you have learned is twelve unrelated facts instead of one. So the drill varies the note it starts from and never names it, and the answer is graded on the distance alone.',
					'The chord drill hides the root for the same reason: m7 is m7 wherever it is played. The root is shown afterwards, with the spelling, because reading it back is worth having too.'
				]
			},
			{
				heading: 'How to work them',
				list: [
					'Play it as many times as you like. Listening again is the drill, not a way round it — the response time targets are set with replays expected.',
					'Sing the two notes back before answering. Matching a distance with your voice is a different, stronger memory than matching it with a name.',
					'On a chord, listen for the 3rd first: minor or major. Then the 7th: how far it leans. The 5th only speaks up when it is flat.',
					'Getting it wrong and then hearing the answer is the rep. Guessing to see the answer is not — the "No idea" button exists so you do not have to.'
				]
			}
		],
		related: ['qualities', 'spelling', 'guide-tones']
	},

	{
		id: 'scheduling',
		title: 'How this app decides what to show you',
		blurb: 'Response time is the grade. Here is what that means.',
		sections: [
			{
				body: [
					'You never rate yourself. The grade comes from whether you were right and how long you took, compared against your own rolling median for that exact card.'
				]
			},
			{
				table: {
					head: ['Grade', 'When'],
					rows: [
						['Again', 'wrong, or you pressed "No idea"'],
						['Hard', `right, but slower than ${HARD_RATIO}× your median`],
						['Good', 'right, at your normal pace'],
						['Easy', `right, and faster than ${EASY_RATIO}× your median`]
					]
				}
			},
			{
				body: [
					'This matters because getting a guide-tone pair right after six seconds of working it out is not the same as knowing it, and a scheduler that treats them alike will graduate cards you cannot actually use.'
				]
			},
			{
				heading: 'Mastery',
				list: [
					`Learning → Familiar: ${FAMILIAR_STREAK} correct in a row.`,
					`Familiar → Automatic: ${AUTOMATIC_STREAK} in a row AND a median under the target — ${TIME_TARGETS.gt.automatic / 1000} seconds for a single chord, ${TIME_TARGETS.chain.automatic / 1000} for a three-chord chain.`,
					`Anything not yet Automatic comes back within ${MAX_DAYS_BEFORE_AUTOMATIC} days, whatever the scheduler would otherwise say.`,
					'New cards are only introduced when the due pile leaves room, so falling behind does not bury you.'
				]
			},
			{
				heading: 'The path',
				body: [
					'The two halves of the app climb separately, and a stage number only means something next to its section: ear stage 2 has nothing to do with theory stage 2.'
				]
			},
			{
				heading: 'Theory',
				list: [
					...pathList('theory'),
					'The Theory screen shows the next stage and what it needs. You can also open any stage by hand in Settings.'
				]
			},
			{
				heading: 'Ear',
				list: [
					...pathList('ear'),
					'The Ear screen shows the same for its own path — and both drills leave the deck entirely when Sound is off, because their whole question is the sound.'
				]
			}
		],
		related: []
	}
];

export const TOPICS_BY_ID: Record<string, ReferenceTopic> = Object.fromEntries(
	TOPICS.map((t) => [t.id, t])
);
