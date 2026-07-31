<script lang="ts">
	/**
	 * The piano used as the answer surface: an octave and a half, C home.
	 *
	 * A fourth below (G–B) and a third above (C–E) flank the home octave, so an
	 * interval "above" a high root can actually be tapped above it and a voicing
	 * can keep its shape instead of folding at the octave seam. The price is key
	 * width — thirteen white keys run ~24px on a 320dp phone — and it is paid
	 * deliberately: real keys are narrow, these are 190px tall (140 on a reveal,
	 * where nothing is tapped), and the drag bubble below names whatever is
	 * under the finger before it commits.
	 *
	 * Answers are still graded on pitch class, so the flanking keys are the same
	 * notes again: tapping either C is tapping C. States the APP asserts about a
	 * pitch class — given, reveal, wrong, previous — light every copy, because
	 * the claim is about the note, not a key. The learner's own SELECTION lights
	 * only the copy that was actually tapped: two keys lighting under one finger
	 * reads as two notes entered, and the point of showing a selection is to
	 * echo the tap, not the theory. Badges (root marker, order numbers) sit on
	 * the home-octave copy only.
	 *
	 * Input commits on RELEASE, not press: put a finger down, slide until the
	 * bubble names the key you meant, let go. A keyboard-only user still gets
	 * click activation (detail 0). White keys are labelled; black keys are not
	 * labelled on the key itself — the bubble shows both spellings, exactly as
	 * much as the aria-label always said — because printing one spelling would
	 * hand over the D♭-versus-C♯ decision the drills train.
	 */

	interface Props {
		/** Controlled: the parent owns the answer and decides what a tap does. */
		selected?: number[];
		/**
		 * Context notes lit as the truth (the chord you're moving from). Still
		 * tappable: a voice-leading answer overlaps the chord it moves from — gtc
		 * holds one guide tone, rlc keeps three of four notes — so a tap on a
		 * given key is a real answer, and `selected` outranks `given` in
		 * `stateOf` for exactly that.
		 */
		given?: number[];
		/** Marks which given note is the root, so the prompt is unambiguous. */
		rootMarker?: number | null;
		/** Text shown on the marked key; guide-tone cards mark the 3rd, not a root. */
		markerLabel?: string;
		/** Correct answer, revealed after checking. */
		reveal?: number[];
		/** Selections that were wrong, shown after checking. */
		wrong?: number[];
		disabled?: boolean;
		/** Visualise-then-place: the keyboard is present but not shown yet. */
		blanked?: boolean;
		/**
		 * Pitch classes to number 1..n, for voicings where the order *is* the
		 * answer. While answering this is what you tapped; on reveal it is the
		 * correct order, because "you played these four notes in the wrong
		 * sequence" is useless feedback without showing the right sequence.
		 */
		orderKeys?: number[] | null;
		/**
		 * Where the hand was: the previous chord of a progression stays lit, a
		 * step dimmer than a live selection. A ii–V–I is played from where the
		 * last chord left you — one note holds, one barely moves — and a keyboard
		 * wiped blank between chords was hiding exactly the relationship the
		 * drill exists to teach. These are the learner's own taps, not the truth.
		 */
		previous?: number[];
		/**
		 * Shorter keys, for a keyboard that is read rather than tapped: every
		 * reveal, and the pair a quality-name card shows as its prompt. The fifty
		 * pixels it gives back are what keeps the panel above and the answer below
		 * on one small phone screen.
		 */
		compact?: boolean;
		/**
		 * Whichever attempt is on screen — the deal, and the step inside it. A
		 * finger already down when the session moves on would otherwise commit its
		 * release onto the NEXT question: it went down while this keyboard was
		 * live, and nothing in the release path can tell that the thing it is
		 * answering changed underneath it. It has to identify the attempt rather
		 * than the question, because a requeued miss can come back as the very
		 * next card and would otherwise read as the same one.
		 */
		asking?: unknown;
		onselect?: (pitchClass: number) => void;
	}

	let {
		selected = [],
		given = [],
		rootMarker = null,
		markerLabel = 'R',
		reveal = [],
		wrong = [],
		disabled = false,
		blanked = false,
		orderKeys = null,
		previous = [],
		compact = false,
		asking = null,
		onselect
	}: Props = $props();

	/** 1-based position of a pitch class in the numbered sequence, or null. */
	function orderOf(pc: number): number | null {
		if (!orderKeys) return null;
		const i = orderKeys.indexOf(pc);
		return i === -1 ? null : i + 1;
	}

	/** home: the octave answers display on; flanks mirror its pc states. */
	const WHITE: { pc: number; letter: string; home: boolean }[] = [
		{ pc: 7, letter: 'G', home: false },
		{ pc: 9, letter: 'A', home: false },
		{ pc: 11, letter: 'B', home: false },
		{ pc: 0, letter: 'C', home: true },
		{ pc: 2, letter: 'D', home: true },
		{ pc: 4, letter: 'E', home: true },
		{ pc: 5, letter: 'F', home: true },
		{ pc: 7, letter: 'G', home: true },
		{ pc: 9, letter: 'A', home: true },
		{ pc: 11, letter: 'B', home: true },
		{ pc: 0, letter: 'C', home: false },
		{ pc: 2, letter: 'D', home: false },
		{ pc: 4, letter: 'E', home: false }
	];

	// `slot` is the index of the white key the black key sits after. slot -1 is
	// the half F♯ clipped by the left edge: without it the leftmost G has no
	// black key on its left and its silhouette reads as a C — the one thing a
	// piano player navigates by is the black-key pattern, so the pattern has to
	// be complete even where the keyboard is cut off.
	const BLACK: { pc: number; slot: number; name: string; home: boolean }[] = [
		{ pc: 6, slot: -1, name: 'F sharp / G flat', home: false },
		{ pc: 8, slot: 0, name: 'G sharp / A flat', home: false },
		{ pc: 10, slot: 1, name: 'A sharp / B flat', home: false },
		{ pc: 1, slot: 3, name: 'C sharp / D flat', home: true },
		{ pc: 3, slot: 4, name: 'D sharp / E flat', home: true },
		{ pc: 6, slot: 6, name: 'F sharp / G flat', home: true },
		{ pc: 8, slot: 7, name: 'G sharp / A flat', home: true },
		{ pc: 10, slot: 8, name: 'A sharp / B flat', home: true },
		{ pc: 1, slot: 10, name: 'C sharp / D flat', home: false },
		{ pc: 3, slot: 11, name: 'D sharp / E flat', home: false }
	];

	const WHITE_COUNT = WHITE.length;

	/**
	 * The white row is a flex row with a 2px gap, so a white key is narrower
	 * than 1/13 of the keyboard. Positioning the black keys on the naive
	 * fraction walked them off their seams — cumulatively, ~2px by the last one
	 * on a 390dp phone, which is a tenth of a black key's width.
	 */
	const KEY_GAP = 2;
	const WHITE_WIDTH = `((100% - ${(WHITE_COUNT - 1) * KEY_GAP}px) / ${WHITE_COUNT})`;
	/** Centre of the gap between white key `slot` and the one after it. */
	const seam = (slot: number) =>
		`(${WHITE_WIDTH} + ${KEY_GAP}px) * ${slot + 1} - ${KEY_GAP / 2}px`;

	/** What the bubble prints. Black keys get both spellings, never one. */
	const BUBBLE_NAME: Record<number, string> = {
		0: 'C',
		1: 'C♯ · D♭',
		2: 'D',
		3: 'D♯ · E♭',
		4: 'E',
		5: 'F',
		6: 'F♯ · G♭',
		7: 'G',
		8: 'G♯ · A♭',
		9: 'A',
		10: 'A♯ · B♭',
		11: 'B'
	};

	/**
	 * Which physical copy each selected pitch class was tapped on, so the
	 * selection fill can echo the tap instead of lighting every copy of the
	 * note. Falls back to the home copy for a selection with no recorded tap
	 * (a revisited chain step). Grading never sees this — it is display only.
	 */
	let origins = $state<Record<number, string>>({});

	const HOME_ID: Record<number, string> = {};
	for (const [i, k] of WHITE.entries()) if (k.home) HOME_ID[k.pc] = `w${i}`;
	for (const [i, k] of BLACK.entries()) if (k.home) HOME_ID[k.pc] = `b${i}`;

	// Selections the parent drops (deselect, FIFO eviction, a step change)
	// take their tap record with them, so a later re-select defaults home.
	$effect(() => {
		const keep = new Set(selected);
		if (Object.keys(origins).some((pc) => !keep.has(Number(pc)))) {
			origins = Object.fromEntries(
				Object.entries(origins).filter(([pc]) => keep.has(Number(pc)))
			);
		}
	});

	function toggle(pc: number, keyId?: string) {
		if (disabled || blanked) return;
		if (!selected.includes(pc) && keyId) origins = { ...origins, [pc]: keyId };
		onselect?.(pc);
	}

	/** Whether THIS copy displays the selection of its pitch class. */
	function selectedHere(pc: number, keyId: string): boolean {
		return stateOf(pc) === 'selected' && (origins[pc] ?? HOME_ID[pc]) === keyId;
	}

	/**
	 * The fill for one physical key. pc-level states that assert something
	 * about the NOTE (reveal, wrong, given) light every copy; the selection
	 * echoes the tap, so a selected pc's other copies fall through to whatever
	 * else is true of them.
	 */
	function keyState(pc: number, keyId: string): string {
		const s = stateOf(pc);
		if (s !== 'selected') return s;
		if (selectedHere(pc, keyId)) return 'selected';
		return given.includes(pc) ? 'given' : '';
	}

	/**
	 * The accessible name carries whatever the fill is saying.
	 *
	 * Every pc-keyed state on this keyboard is a colour and nothing else — the
	 * lit prompt notes, the marked 3rd, the revealed answer, the order a
	 * rootless voicing is tapped in — and the badges that do carry text sit
	 * inside a button whose aria-label replaces them. A gtn card is two lit keys
	 * and a marker: read out as thirteen bare letters it has no prompt in it at
	 * all. `selected` is left to aria-pressed, which is what that state is.
	 */
	function keyLabel(base: string, pc: number, home: boolean): string {
		const s = stateOf(pc);
		const parts = [base];
		if (s === 'given') parts.push('lit');
		else if (s === 'reveal') parts.push('correct');
		else if (s === 'wrong') parts.push('wrong');
		// Same guard the ghost fill carries: a key tapped for THIS chord is a live
		// selection, and announcing it as the one before contradicts aria-pressed
		// on the very tap that just set it.
		else if (s === '' && previous.includes(pc)) parts.push('previous chord');
		if (home && rootMarker === pc) parts.push(`marked ${markerLabel}`);
		else if (home && orderOf(pc)) parts.push(`note ${orderOf(pc)}`);
		return parts.join(', ');
	}

	function stateOf(pc: number): string {
		if (reveal.includes(pc)) return 'reveal';
		if (wrong.includes(pc)) return 'wrong';
		if (selected.includes(pc)) return 'selected';
		if (given.includes(pc)) return 'given';
		return '';
	}

	// ------------------------------------------------------------------
	// Press-drag-release input, with a bubble naming the key under the
	// finger. The finger hides exactly the key it is about to press — worse
	// now the keys are narrow — so the name floats above it, and the commit
	// waits for the release so a slide can correct a near-miss for free.
	// ------------------------------------------------------------------
	// $state for the compiler's sake only; nothing re-renders off it.
	let container = $state<HTMLDivElement | null>(null);
	// The bubble, unlike the container, is genuinely reactive: track() reassigns
	// it on every pointermove and the preview is drawn from it.
	let bubble = $state<{ x: number; y: number; label: string; pc: number; keyId?: string } | null>(null);
	/**
	 * Every finger down, not just the first, each with where it last was. A
	 * guide-tone pair is two keys and gets tapped as two keys: with only the
	 * primary pointer tracked, the second finger committed nothing — it raises no
	 * compatibility mouse event either, so the key was silently lost and Check
	 * stayed disabled. The positions are what lets the bubble fall back to a
	 * finger still down when the one it was naming lifts, and what every finger
	 * commits on its own release.
	 */
	const active = new Map<number, { x: number; y: number }>();
	/** Which finger the bubble is currently naming. */
	let owner: number | null = null;

	// Reading `asking` is the whole point of the statement: nothing here wants
	// its value, only to be re-run when the question changes.
	$effect(() => {
		asking;
		for (const id of active.keys()) {
			if (container?.hasPointerCapture(id)) container.releasePointerCapture(id);
		}
		active.clear();
		owner = null;
		bubble = null;
	});

	/**
	 * Half the widest bubble ("G♯ · A♭" at ~66px), because it is centred on the
	 * finger: clamping tighter than that hangs the outermost keys' label off the
	 * screen, and those are the keys most likely to be mis-hit.
	 */
	const BUBBLE_INSET = 36;

	/**
	 * The nearest key horizontally, among those the point is level with. The 2px
	 * flex gap between white keys belongs to no key at all, and three of those
	 * seams (B|C, E|F) have no black key covering them for the full height — a
	 * press that landed in one named nothing in the bubble and committed nothing
	 * on release, which is a tap silently lost on a surface whose whole promise
	 * is that it tells you what it is about to do.
	 */
	function nearestKey(clientX: number, clientY: number): Element | null {
		let best: Element | null = null;
		let bestDx = Infinity;
		for (const el of Array.from(container?.querySelectorAll('[data-kb-pc]') ?? [])) {
			const r = el.getBoundingClientRect();
			if (clientY < r.top || clientY >= r.bottom) continue;
			const dx = Math.max(r.left - clientX, clientX - r.right, 0);
			if (dx < bestDx) {
				best = el;
				bestDx = dx;
			}
		}
		return best;
	}

	function keyAt(
		clientX: number,
		clientY: number
	): { pc: number; keyId?: string; label: string } | null {
		const hit = document.elementFromPoint(clientX, clientY);
		// Outside the keyboard is genuinely nothing — dragging off the keys has to
		// clear the bubble. Inside it, every point belongs to a key.
		if (!hit || !container?.contains(hit)) return null;
		const el = hit.closest('[data-kb-pc]') ?? nearestKey(clientX, clientY);
		if (!el) return null;
		const pc = Number(el.getAttribute('data-kb-pc'));
		return { pc, keyId: el.getAttribute('data-kb-key') ?? undefined, label: BUBBLE_NAME[pc] ?? '' };
	}

	function bubbleAt(clientX: number, clientY: number) {
		const rect = container?.getBoundingClientRect();
		const key = keyAt(clientX, clientY);
		if (!rect || !key) return null;
		return {
			x: Math.min(Math.max(clientX - rect.left, BUBBLE_INSET), rect.width - BUBBLE_INSET),
			y: clientY - rect.top,
			label: key.label,
			pc: key.pc,
			keyId: key.keyId
		};
	}

	/**
	 * Hand the bubble to a finger that is still down, most recent first, or clear
	 * it if none of them is on a key. The bubble is the whole of the
	 * slide-until-it-says-what-you-meant contract, so one naming a finger that
	 * has already lifted describes neither what is under the hand nor what the
	 * next release will commit.
	 */
	function rebubble(exclude: number | null = null) {
		for (const [id, at] of [...active].reverse()) {
			if (id === exclude) continue;
			const b = bubbleAt(at.x, at.y);
			if (b) {
				owner = id;
				bubble = b;
				return;
			}
		}
		owner = null;
		bubble = null;
	}

	function track(e: PointerEvent) {
		active.set(e.pointerId, { x: e.clientX, y: e.clientY });
		const b = bubbleAt(e.clientX, e.clientY);
		if (b) {
			owner = e.pointerId;
			bubble = b;
		} else if (owner === e.pointerId || owner === null) {
			// Dragged off the keys. Only the finger that owns the bubble may take it
			// away, and only if no other finger can hold it.
			rebubble(e.pointerId);
		}
	}

	function onPointerDown(e: PointerEvent) {
		if (disabled || blanked) return;
		// Contact only. A right-click or a pen barrel-button press raises the same
		// down/up pair, and committing on it puts a note the learner never played
		// into the answer — where, with `.slice(-need)`, it also evicts a real one.
		// Touch and pen contact both report button 0.
		if (e.button !== 0) return;
		active.set(e.pointerId, { x: e.clientX, y: e.clientY });
		container?.setPointerCapture(e.pointerId);
		track(e);
	}

	function onPointerMove(e: PointerEvent) {
		if (!active.has(e.pointerId)) return;
		track(e);
	}

	function onPointerUp(e: PointerEvent) {
		// The other half of the contact guard. A secondary button released while
		// the primary is still down carries the SAME pointerId, so committing on
		// it would toggle whatever key the finger is over and then swallow the
		// real release, which finds nothing left to delete.
		if (e.button > 0) return;
		const at = active.get(e.pointerId);
		if (!at) return;
		active.delete(e.pointerId);
		// Commit where the finger last WAS, not where the release says it is: a
		// lift-off roll across a ~24px key seam can land the pointerup on the
		// neighbour with no move event in between. For the finger the bubble names
		// that is the bubble, which is the promise; for any other finger it is its
		// own last tracked position, which is the key its bubble would have named.
		const hit =
			owner === e.pointerId && bubble
				? { pc: bubble.pc, keyId: bubble.keyId }
				: keyAt(at.x, at.y);
		if (owner === e.pointerId || active.size === 0) rebubble();
		if (hit && hit.pc !== undefined) toggle(hit.pc, hit.keyId);
	}

	function onPointerCancel(e: PointerEvent) {
		if (!active.delete(e.pointerId)) return;
		if (owner === e.pointerId || active.size === 0) rebubble();
	}

	/**
	 * Keyboard users activate with Enter/Space, which fires click with
	 * detail 0. Pointer input is already committed on pointerup, so a click
	 * with detail > 0 would be a double toggle and is ignored.
	 */
	function onKeyActivate(e: MouseEvent, pc: number, keyId: string) {
		if (e.detail === 0) toggle(pc, keyId);
	}
</script>

{#if blanked}
	<!-- Motor imagery: the keys are not rendered at all, so there is nothing to
	     read off the screen while you picture the shape. -->
	<div
		class="-mx-4 flex h-[190px] items-center justify-center border border-dashed border-line text-sm text-muted"
		data-testid="keyboard"
		data-blanked="true"
	>
		See it in your head…
	</div>
{:else}
	<!-- Full-bleed: thirteen keys need every pixel a phone has. touch-action none
	     while it is live, because the drag IS the input and the page must not pan
	     with it — but only then: a prompt keyboard and every reveal are read
	     rather than tapped, and a 190px band that swallows the swipe is a dead
	     zone on a screen that has to scroll. -->
	<div
		bind:this={container}
		class="no-select relative -mx-4"
		class:touch-none={!disabled}
		data-testid="keyboard"
		data-blanked="false"
		role="group"
		aria-label="Piano keyboard"
		onpointerdown={onPointerDown}
		onpointermove={onPointerMove}
		onpointerup={onPointerUp}
		onpointercancel={onPointerCancel}
	>
		<div class="flex w-full gap-[2px]" style="height: {compact ? 140 : 190}px">
			{#each WHITE as key, i (i)}
				{@const s = keyState(key.pc, `w${i}`)}
				<button
					type="button"
					class="key-white relative min-w-0 flex-1 rounded-b-sm border border-line pb-2 text-center align-bottom text-xs font-semibold transition-colors"
					class:is-flank={!key.home}
					class:is-prev={previous.includes(key.pc) && stateOf(key.pc) === ''}
					class:is-selected={s === 'selected'}
					class:is-given={s === 'given'}
					class:is-reveal={s === 'reveal'}
					class:is-wrong={s === 'wrong'}
					data-kb-pc={key.pc}
					data-kb-key={`w${i}`}
					data-pc={key.home ? key.pc : undefined}
					data-flank-pc={key.home ? undefined : key.pc}
					data-state={s}
					data-prev={previous.includes(key.pc) && stateOf(key.pc) === ''}
					aria-pressed={selectedHere(key.pc, `w${i}`)}
					aria-label={keyLabel(key.letter, key.pc, key.home)}
					{disabled}
					onclick={(e) => onKeyActivate(e, key.pc, `w${i}`)}
				>
					<!-- Badges sit above the letter, not at the top: the top half of a
					     white key is covered by its neighbouring black keys. Home copy
					     only — one "R" is a marker, three are a pattern to decode. -->
					{#if key.home && rootMarker === key.pc}
						<span class="absolute inset-x-0 bottom-7 text-[10px] font-bold" aria-hidden="true"
							>{markerLabel}</span
						>
					{:else if key.home && orderOf(key.pc)}
						<span
							class="absolute inset-x-0 bottom-7 text-[11px] font-bold"
							data-order={orderOf(key.pc)}>{orderOf(key.pc)}</span
						>
					{/if}
					<span class="absolute inset-x-0 bottom-2">{key.letter}</span>
				</button>
			{/each}
		</div>

		{#each BLACK as key, i (i)}
			{@const s = keyState(key.pc, `b${i}`)}
			<button
				type="button"
				class="key-black absolute top-0 rounded-b-sm border border-black transition-colors"
				class:is-flank={!key.home}
				class:is-prev={previous.includes(key.pc) && stateOf(key.pc) === ''}
				class:is-selected={s === 'selected'}
				class:is-given={s === 'given'}
				class:is-reveal={s === 'reveal'}
				class:is-wrong={s === 'wrong'}
				style="{key.slot < 0
					? `left: 0; width: calc(${WHITE_WIDTH} * 0.34)`
					: `left: calc(${seam(key.slot)} - ${WHITE_WIDTH} * 0.34); width: calc(${WHITE_WIDTH} * 0.68)`}; height: {compact ? 87 : 118}px"
				data-kb-pc={key.pc}
				data-kb-key={`b${i}`}
				data-pc={key.home ? key.pc : undefined}
				data-flank-pc={key.home ? undefined : key.pc}
				data-state={s}
				data-prev={previous.includes(key.pc) && stateOf(key.pc) === ''}
				aria-pressed={selectedHere(key.pc, `b${i}`)}
				aria-label={keyLabel(key.name, key.pc, key.home)}
				{disabled}
				onclick={(e) => onKeyActivate(e, key.pc, `b${i}`)}
			>
				{#if key.home && rootMarker === key.pc}
					<!-- Inherits the key's ink: the root marker only appears on given keys,
					     whose brass fill needs dark text, not the black key's ivory. -->
					<span class="absolute inset-x-0 bottom-2 text-[10px] font-bold" aria-hidden="true"
						>{markerLabel}</span
					>
				{:else if key.home && orderOf(key.pc)}
					<span
						class="absolute inset-x-0 bottom-2 text-[11px] font-bold"
						data-order={orderOf(key.pc)}>{orderOf(key.pc)}</span
					>
				{/if}
			</button>
		{/each}

		{#if bubble && !disabled}
			<!-- Above the finger, clamped to the keyboard's width. aria-hidden:
			     it repeats what the key's own label already announces. -->
			<div
				class="pointer-events-none absolute z-20 -translate-x-1/2 border border-line bg-surface-2 px-2.5 py-1.5 text-sm font-semibold whitespace-nowrap shadow-lg"
				style="left: {bubble.x}px; top: {Math.max(bubble.y - 64, -14)}px"
				aria-hidden="true"
				data-testid="key-bubble"
			>
				{bubble.label}
			</div>
		{/if}
	</div>
{/if}

<style>
	/* Ivory and ebony, the materials themselves — warm, not the blue-grey of a
	   default UI. The keys are the one place in the app that is light. */
	.key-white {
		background: #ece4d6;
		color: #1a1512;
	}
	.key-white:active {
		background: #d5cbba;
	}
	.key-black {
		background: #100e0c;
		color: #ece4d6;
		z-index: 10;
	}
	.key-black:active {
		background: #2c2723;
	}

	/* The flanking half-octaves are context, and read a shade darker — like the
	   keys beyond where the lamp is pointed. State fills below override this,
	   because a lit note is lit wherever its copy sits. */
	.key-white.is-flank {
		background: #ddd2bf;
		color: #4a4238;
	}
	.key-black.is-flank {
		background: #1c1815;
	}

	/* Where the hand still is: the previous chord of a progression stays lit,
	   a step dimmer than a live selection. Luminance, not hue, so it reads
	   under any colour vision and keeps the three hues for right/wrong/given. */
	.key-white.is-prev {
		background: #c9bca6;
		border-color: #c9bca6;
	}
	.key-black.is-prev {
		background: #4a423a;
	}

	/* A key you have chosen is a key you have pressed, so it inverts: the white
	   one goes to ebony, the black one to ivory. Luminance carries it, which
	   means it survives any colour vision — and it leaves all three hues free
	   for the states that are about being right or wrong. */
	.key-white.is-selected {
		background: #1a1512;
		color: var(--color-ink);
		border-color: #1a1512;
	}
	.key-black.is-selected {
		background: var(--color-ink);
		color: #1a1512;
		border-color: var(--color-ink);
	}
	/* Brass: these keys carry the question. Grey would read as "disabled" — the
	   opposite of "start here" — and brass is the app's colour for what it is
	   telling you, as against what you or the grader said. Dark ink on the
	   fill, identical on white and black keys. */
	.is-given {
		background: var(--color-brass) !important;
		color: #2a1e07 !important;
		border-color: var(--color-brass) !important;
	}
	.is-reveal {
		background: var(--color-sage) !important;
		color: #0f2409 !important;
		border-color: var(--color-sage) !important;
	}
	/* Felt is the darkest of the three fills but not dark enough for a tinted
	   ink: the key letter is 12px semibold, so it needs 4.5:1, and the warmer
	   #f7e6e4 this used to carry measures 4.13:1. Nearly-white gets it to 4.55. */
	.is-wrong {
		background: var(--color-felt) !important;
		color: #fdf2f1 !important;
		border-color: var(--color-felt) !important;
	}

	button:disabled {
		cursor: default;
	}
</style>
