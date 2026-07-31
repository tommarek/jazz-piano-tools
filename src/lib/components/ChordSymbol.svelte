<script lang="ts">
	/**
	 * A chord symbol set the way a plate engraver sets one.
	 *
	 * On a lead sheet the root is the note and everything after it is a
	 * modifier, and the setting says so: the letter at full size, the accidental
	 * raised and tucked in against it, the quality lifted clear as a superscript.
	 * Every app that renders "Bbmaj7" as one flat run of text is throwing that
	 * hierarchy away — and the hierarchy is exactly what the eye needs when the
	 * card is on screen for two seconds.
	 *
	 * Prose passes through untouched, because these strings are not always
	 * symbols: card titles run from "C♯m7♭5" to "Which chord could this be?" to
	 * "Dm7 → G7", and one of them has to survive contact with the others.
	 */

	interface Props {
		/** A symbol, or a whole title with symbols in it. */
		text: string;
		/**
		 * 'display' is the full engraving, for anything 24px and up. 'inline'
		 * keeps the accidental but barely lifts the quality: a true superscript
		 * of a 12px chain tab is 7px, which is a smudge, not a chord.
		 */
		size?: 'display' | 'inline';
		class?: string;
	}

	let { text, size = 'display', class: className = '' }: Props = $props();

	/**
	 * A root, an optional accidental, and a quality made only of the things a
	 * quality is made of. Anchored at both ends so a word from an instruction
	 * cannot half-match: "Cmaj7" engraves, "Come back tomorrow" does not.
	 *
	 * The trailing group is the punctuation an answer line puts a symbol in
	 * front of — "Dm7: F–C", "Cmaj7, Am7". Rejecting the whole token over it
	 * printed those symbols flat, and a gtn reading with three of them set two
	 * as prose and the last as a chord on one line.
	 */
	const CHORD = /^([A-G])([♭♯]?)((?:maj|min|m|°|ø|alt|sus|add|dim|[+\-()0-9♭♯]|7|9|11|13)*)([,:;.]?)$/;

	interface Part {
		text: string;
		root?: string;
		accidental?: string;
		quality?: string;
		tail?: string;
	}

	/** Splits on spaces so the arrow, "in", "major" and the rest stay prose. */
	const parts = $derived.by((): Part[] =>
		text.split(/(\s+)/).map((token) => {
			const m = CHORD.exec(token);
			// A bare letter is a note name, not a chord — engraving is just the
			// letter, and the branch below happens to render exactly that.
			if (!m) return { text: token };
			return { text: token, root: m[1], accidental: m[2], quality: m[3], tail: m[4] };
		})
	);
</script>

<!--
	Every span below is inline and the markup carries no whitespace between them,
	which is the whole trick: a chord symbol has to stay ONE run of text. Laid out
	as flex items, or split across lines, the browser reads "B♭maj7" back as
	"B ♭ maj7" — which is what a screen reader announces, what a copy-paste
	yields, and what an assertion on the visible answer sees. prettier-ignore
	keeps a formatter from putting the spaces back.
-->
<!-- prettier-ignore -->
<span class={className}>{#each parts as part, i (i)}{#if part.root}<span class="whitespace-nowrap"><span>{part.root}</span>{#if part.accidental}<span class="relative" style="font-size:0.66em; top:{size === 'display' ? '-0.42em' : '-0.26em'}; margin-left:-0.04em">{part.accidental}</span>{/if}{#if part.quality}<span class="relative font-semibold" style="font-size:{size === 'display' ? '0.5em' : '0.8em'}; top:{size === 'display' ? '-0.72em' : '-0.14em'}; margin-left:0.05em; letter-spacing:0.02em">{part.quality}</span>{/if}{#if part.tail}{part.tail}{/if}</span>{:else}{part.text}{/if}{/each}</span>
