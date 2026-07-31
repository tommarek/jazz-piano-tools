<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import { effectiveCardTypes, saveSettings } from '$lib/data/settings';
	import { eligibleIds } from '$lib/data/queue';
	import { downloadExport, importExport } from '$lib/data/export';
	import { resetAll } from '$lib/db';
	import type { Quality } from '$lib/music/voicings';
	import { EAR_TYPES, SECTIONS, type CardType } from '$lib/music/cards';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	// A working copy, so nothing is written until Save.
	// svelte-ignore state_referenced_locally
	let s = $state({ ...data.settings });
	let status = $state<{ kind: 'ok' | 'error'; text: string } | null>(null);
	let busy = $state(false);
	let fileInput = $state<HTMLInputElement | null>(null);

	function toggle<T>(list: T[], value: T, on: boolean): T[] {
		return on ? [...new Set([...list, value])] : list.filter((v) => v !== value);
	}

	async function save(event: SubmitEvent) {
		event.preventDefault();
		const pending = $state.snapshot(s);
		if (pending.activeQualities.length === 0) {
			status = { kind: 'error', text: 'Keep at least one chord quality.' };
			return;
		}
		if (pending.activeCardTypes.length === 0) {
			status = { kind: 'error', text: 'Keep at least one drill type.' };
			return;
		}
		// What the deck actually draws from is narrower than the ticked list: a
		// drill in an unopened stage is not dealt, and the ear drills are the
		// sound. Guarding the ticked list alone let both empty the deck for good,
		// with nothing on Today able to say why it never has anything for you.
		const live = effectiveCardTypes(pending).filter(
			(t) => pending.soundEnabled || !EAR_TYPES.includes(t)
		);
		if (live.length === 0) {
			const unreachable = effectiveCardTypes(pending).length === 0;
			status = {
				kind: 'error',
				text: unreachable
					? 'Every drill left on belongs to a stage that is not open yet, so the deck would be empty. Keep one from an open stage, or open the stage below.'
					: 'The only drills left on are the ear ones, and "Play the answer" is off — they leave the deck with it, so the deck would be empty.'
			};
			return;
		}
		busy = true;
		try {
			// Types and qualities are ticked in two separate lists but filter one
			// deck, and which qualities a drill can even reach depends on the drill:
			// chain alone with maj7 off leaves no ii–V–I at all, so both lists pass
			// their own check and the deck is still empty. Ask the deck itself.
			//
			// Section by section, because the two halves are separate practices: an
			// ear-only configuration is a legitimate one, and asking the theory deck
			// alone refused it with a message about chord qualities that was false.
			const perSection = await Promise.all(
				SECTIONS.map((section) => eligibleIds(pending, { kind: 'section', section }))
			);
			if (perSection.every((ids) => ids.size === 0)) {
				status = {
					kind: 'error',
					text: 'No card matches both the drills and the chord qualities you kept, so the deck would be empty. Turn another chord quality back on, or another drill.'
				};
				return;
			}
			const saved = await saveSettings(pending);
			s = { ...saved };
			status = { kind: 'ok', text: 'Saved.' };
			await invalidateAll();
		} catch (err) {
			status = { kind: 'error', text: err instanceof Error ? err.message : 'Could not save' };
		} finally {
			busy = false;
		}
	}

	async function onImport(event: Event) {
		const file = (event.target as HTMLInputElement).files?.[0];
		if (!file) return;
		busy = true;
		try {
			const payload = JSON.parse(await file.text());
			const { reviews } = await importExport(payload);
			status = { kind: 'ok', text: `Imported ${reviews} reviews. Reopening…` };
			location.reload();
		} catch (err) {
			status = { kind: 'error', text: err instanceof Error ? err.message : 'Import failed' };
		} finally {
			busy = false;
			// Picking the same file twice fires no change event unless the input is
			// cleared, so a failed import could not be retried after fixing the file.
			(event.target as HTMLInputElement).value = '';
		}
	}

	async function eraseEverything() {
		// A destructive, irreversible action on the only copy of the data.
		if (!confirm('Erase all practice history and settings on this device? This cannot be undone.')) return;
		await resetAll();
		location.reload();
	}
</script>

<svelte:head><title>Settings · Comp</title></svelte:head>

<header class="mb-6">
	<h1 class="text-2xl font-bold uppercase" style="font-stretch:118%; letter-spacing:0.16em">
		Settings
	</h1>
	<div class="rule-brass mt-1.5"></div>
</header>

{#if status}
	<p
		class="mb-4 border-l-2 py-2 pr-2 pl-3 text-xs {status.kind === 'ok'
			? 'border-sage bg-sage/10 text-sage'
			: 'border-felt bg-felt/10 text-felt-ink'}"
		role={status.kind === 'ok' ? 'status' : 'alert'}
	>
		{status.text}
	</p>
{/if}

<form onsubmit={save} class="space-y-8">
	<section>
		<h2 class="eyebrow mb-4">Session</h2>

		<label class="mb-3 block">
			<span class="text-sm">Length cap</span>
			<span class="ml-1 text-xs text-muted">minutes</span>
			<input
				type="number"
				name="sessionMinutes"
				min="1"
				max="30"
				bind:value={s.sessionMinutes}
				class="mt-1.5 min-h-[44px] w-full border border-line bg-surface px-3"
			/>
		</label>

		<label class="mb-3 block">
			<span class="text-sm">Card cap</span>
			<input
				type="number"
				name="sessionCardCap"
				min="5"
				max="200"
				bind:value={s.sessionCardCap}
				class="mt-1.5 min-h-[44px] w-full border border-line bg-surface px-3"
			/>
		</label>

		<label class="block">
			<span class="text-sm">New cards per day</span>
			<input
				type="number"
				name="newCardsPerDay"
				min="0"
				max="50"
				bind:value={s.newCardsPerDay}
				class="mt-1.5 min-h-[44px] w-full border border-line bg-surface px-3"
			/>
		</label>

		<label class="mt-3 block">
			<span class="text-sm">Visualise delay</span>
			<span class="ml-1 text-xs text-muted">ms, 0 = off</span>
			<input
				type="number"
				min="0"
				max="10000"
				step="500"
				bind:value={s.visualiseDelayMs}
				class="mt-1.5 min-h-[44px] w-full border border-line bg-surface px-3"
			/>
			<span class="mt-1 block text-xs text-muted">
				Blanks the keyboard so you picture the shape before placing it.
			</span>
		</label>

		<label class="mt-3 flex min-h-[44px] items-start gap-2">
			<input
				type="checkbox"
				bind:checked={s.instantAnswer}
				class="mt-0.5 size-5 shrink-0"
				data-testid="instant-answer"
			/>
			<span>
				<span class="block text-sm">Answer on tap</span>
				<span class="block text-[11px] text-muted">
					Drills with one thing to name — quality, mode, interval — submit as soon as you tap,
					with no Check. Faster, but a mis-tap is the answer. Drills that ask for a root as well,
					or for keys, always wait for Check.
				</span>
			</span>
		</label>

		<label class="mt-3 flex min-h-[44px] items-start gap-2">
			<input
				type="checkbox"
				bind:checked={s.soundEnabled}
				class="mt-0.5 size-5 shrink-0"
				data-testid="sound-enabled"
			/>
			<span>
				<span class="block text-sm">Play the answer</span>
				<span class="block text-[11px] text-muted">
					Sounds each voicing when it is revealed, so the shape gets an ear as well as a hand. The
					two ear drills are the sound — with this off they leave the deck entirely.
				</span>
			</span>
		</label>
	</section>

	<section>
		<div class="rule mb-4"></div>
		<h2 class="eyebrow mb-1">Deck</h2>
		<p class="mb-3 text-xs text-muted">
			Interleaving is the point — leave several on rather than drilling one at a time.
		</p>

		<fieldset class="mb-3">
			<legend class="eyebrow mb-2">Chord qualities</legend>
			{#each data.qualities as q (q.value)}
				<label class="flex min-h-[44px] items-center gap-2">
					<input
						type="checkbox"
						value={q.value}
						data-testid="quality-{q.value}"
						checked={s.activeQualities.includes(q.value)}
						onchange={(e) =>
							(s.activeQualities = toggle(
								s.activeQualities,
								q.value as Quality,
								e.currentTarget.checked
							))}
						class="size-5"
					/>
					<span class="text-sm">{q.label}</span>
				</label>
			{/each}
		</fieldset>

		<fieldset>
			<legend class="eyebrow mb-2">Drill types · theory</legend>
			{#each data.stages as stage (stage.n)}
				<div class="eyebrow mt-4 mb-2 flex items-center gap-2">
					Stage {stage.n} — {stage.title}
					{#if stage.n > s.unlockedStages}<span class="normal-case">· not yet</span>{/if}
				</div>
				{#each stage.types as t (t.value)}
					{@const locked = stage.n > s.unlockedStages}
					<label class="flex min-h-[44px] items-start gap-2 py-1">
						<!-- A locked drill is not dealt whatever this says, so leaving it
						     tickable let it stand in for a real choice and empty the deck.
						     Muted rather than faded, like the ear fieldset below: opacity
						     over the 11px hint lands it at 3.1:1, a row you cannot read
						     rather than one you cannot tick. -->
						<input
							type="checkbox"
							value={t.value}
							checked={s.activeCardTypes.includes(t.value)}
							disabled={locked}
							onchange={(e) =>
								(s.activeCardTypes = toggle(
									s.activeCardTypes,
									t.value as CardType,
									e.currentTarget.checked
								))}
							class="mt-0.5 size-5 shrink-0"
							data-testid="cardtype-{t.value}"
						/>
						<span>
							<span class="block text-sm" class:text-muted={locked}>{t.label}</span>
							<span class="block text-[11px] text-muted">{t.hint}</span>
						</span>
					</label>
				{/each}
			{/each}
		</fieldset>

		<fieldset class="mt-4">
			<legend class="eyebrow mb-2">Drill types · ear</legend>
			{#each data.earStages as stage (stage.n)}
				{@const locked = stage.n > s.earUnlockedStages}
				{#each stage.types as t (t.value)}
					<label class="flex min-h-[44px] items-start gap-2 py-1">
						<input
							type="checkbox"
							value={t.value}
							checked={s.activeCardTypes.includes(t.value)}
							disabled={locked}
							onchange={(e) =>
								(s.activeCardTypes = toggle(
									s.activeCardTypes,
									t.value as CardType,
									e.currentTarget.checked
								))}
							class="mt-0.5 size-5 shrink-0"
							data-testid="cardtype-{t.value}"
						/>
						<span>
							<span class="block text-sm" class:text-muted={locked}>
								{t.label}{locked ? ' · not yet' : ''}
							</span>
							<span class="block text-[11px] text-muted">{t.hint}</span>
						</span>
					</label>
				{/each}
			{/each}
		</fieldset>
	</section>

	<section>
		<div class="rule mb-4"></div>
		<h2 class="eyebrow mb-1">The path</h2>
		<p class="mb-2 text-xs text-muted">
			Stages open by practice — the Theory screen shows what the next one needs. Impatient? Open a
			stage here; the deck grows the moment you save.
		</p>

		<label class="flex min-h-[44px] items-center gap-2">
			<input type="checkbox" bind:checked={s.stageAutoUnlock} class="size-5" />
			<span class="text-sm">Open the next stage automatically when it is earned</span>
		</label>

		<div class="eyebrow mt-4 mb-1">Theory</div>
		{#each data.stages as stage (stage.n)}
			<div class="flex min-h-[44px] items-center gap-2">
				<span class="flex-1 text-sm">
					{stage.n}. {stage.title}
				</span>
				{#if stage.n <= s.unlockedStages}
					<span class="eyebrow !text-sage">open</span>
				{:else}
					<button
						type="button"
						class="eyebrow min-h-[44px] border border-line px-3 !text-brass"
						data-testid="open-stage-{stage.n}"
						onclick={() => (s.unlockedStages = stage.n)}>Open now</button
					>
				{/if}
			</div>
		{/each}

		<!-- A separate ladder, so a separate list: opening a voicings stage has
		     never said anything about what you can hear. -->
		<div class="eyebrow mt-4 mb-1">Ear</div>
		{#each data.earStages as stage (stage.n)}
			<div class="flex min-h-[44px] items-center gap-2">
				<span class="flex-1 text-sm">{stage.n}. {stage.title}</span>
				{#if stage.n <= s.earUnlockedStages}
					<span class="eyebrow !text-sage">open</span>
				{:else}
					<button
						type="button"
						class="eyebrow min-h-[44px] border border-line px-3 !text-brass"
						data-testid="open-ear-stage-{stage.n}"
						onclick={() => (s.earUnlockedStages = stage.n)}>Open now</button
					>
				{/if}
			</div>
		{/each}
	</section>

	<section>
		<div class="rule mb-4"></div>
		<h2 class="eyebrow mb-3">Scheduling</h2>

		<label class="mb-3 block">
			<span class="text-sm">Target retention</span>
			<span class="ml-1 text-xs text-muted">%</span>
			<input
				type="number"
				min="70"
				max="98"
				value={Math.round(s.targetRetention * 100)}
				oninput={(e) => {
					// An emptied field is a number being retyped, not 0%. Number('') is 0,
					// which is finite, so sanitise() clamps it to the 70% floor instead of
					// falling back — the one field here not on bind:value, which gives null.
					const v = e.currentTarget.value;
					if (v !== '') s.targetRetention = Number(v) / 100;
				}}
				class="mt-1.5 min-h-[44px] w-full border border-line bg-surface px-3"
			/>
			<span class="mt-1 block text-xs text-muted">
				Higher means more reviews per day. 90% is the sensible default.
			</span>
		</label>
	</section>

	<button
		type="submit"
		disabled={busy}
		class="eyebrow min-h-[56px] w-full rounded-sm bg-brass !text-on-brass disabled:opacity-50"
		style="font-size:0.8125rem"
		data-testid="save-settings">Save</button
	>
</form>

<section class="mt-10">
	<div class="rule mb-4"></div>
	<h2 class="eyebrow mb-2">Your data</h2>
	<p class="mb-3 text-xs text-muted">
		Everything lives on this device and nowhere else. Nothing is uploaded, so a backup is your
		responsibility — and a new phone needs an export.
	</p>

	<button
		type="button"
		onclick={downloadExport}
		class="flex min-h-[44px] w-full items-center text-sm text-brass underline underline-offset-2"
		data-testid="export-link">Export everything as JSON</button
	>

	<button
		type="button"
		onclick={() => fileInput?.click()}
		class="flex min-h-[44px] w-full items-center text-sm text-brass underline underline-offset-2"
		data-testid="import-link">Import a backup</button
	>
	<input
		bind:this={fileInput}
		type="file"
		accept="application/json,.json"
		class="hidden"
		onchange={onImport}
	/>

	<button
		type="button"
		onclick={eraseEverything}
		class="flex min-h-[44px] w-full items-center text-sm text-felt-ink underline underline-offset-2"
		data-testid="erase-link">Erase all practice history &amp; settings</button
	>
</section>
