<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import { saveSettings } from '$lib/data/settings';
	import { GATE_PER_CHORD_MS } from '$lib/data/stages';
	import { downloadExport, importExport } from '$lib/data/export';
	import { resetAll } from '$lib/db';
	import type { Quality } from '$lib/music/voicings';
	import type { CardType } from '$lib/music/cards';
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
		if (s.activeQualities.length === 0) {
			status = { kind: 'error', text: 'Keep at least one chord quality.' };
			return;
		}
		if (s.activeCardTypes.length === 0) {
			status = { kind: 'error', text: 'Keep at least one drill type.' };
			return;
		}
		busy = true;
		try {
			const saved = await saveSettings($state.snapshot(s));
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
		}
	}

	async function eraseEverything() {
		// A destructive, irreversible action on the only copy of the data.
		if (!confirm('Erase all practice history and settings on this device? This cannot be undone.')) return;
		await resetAll();
		location.reload();
	}
</script>

<svelte:head><title>Settings · Voicings</title></svelte:head>

<h1 class="mb-4 text-lg font-semibold">Settings</h1>

{#if status}
	<p
		class="mb-3 rounded-lg border px-3 py-2 text-xs {status.kind === 'ok'
			? 'border-good/40 bg-good/10 text-good'
			: 'border-bad/40 bg-bad/10 text-bad'}"
		role={status.kind === 'ok' ? 'status' : 'alert'}
	>
		{status.text}
	</p>
{/if}

<form onsubmit={save} class="space-y-4">
	<section class="rounded-xl border border-line bg-surface p-4">
		<h2 class="mb-3 text-[11px] uppercase tracking-wider text-muted">Session</h2>

		<label class="mb-3 block">
			<span class="text-sm">Length cap</span>
			<span class="ml-1 text-xs text-muted">minutes</span>
			<input
				type="number"
				name="sessionMinutes"
				min="1"
				max="30"
				bind:value={s.sessionMinutes}
				class="mt-1 min-h-[44px] w-full rounded-lg border border-line bg-surface-2 px-3"
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
				class="mt-1 min-h-[44px] w-full rounded-lg border border-line bg-surface-2 px-3"
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
				class="mt-1 min-h-[44px] w-full rounded-lg border border-line bg-surface-2 px-3"
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
				class="mt-1 min-h-[44px] w-full rounded-lg border border-line bg-surface-2 px-3"
			/>
			<span class="mt-1 block text-xs text-muted">
				Blanks the keyboard so you picture the shape before placing it.
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

	<section class="rounded-xl border border-line bg-surface p-4">
		<h2 class="mb-1 text-[11px] uppercase tracking-wider text-muted">Deck</h2>
		<p class="mb-3 text-xs text-muted">
			Interleaving is the point — leave several on rather than drilling one at a time.
		</p>

		<fieldset class="mb-3">
			<legend class="mb-1 text-sm">Chord qualities</legend>
			{#each data.qualities as q (q.value)}
				<label class="flex min-h-[44px] items-center gap-2">
					<input
						type="checkbox"
						value={q.value}
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
			<legend class="mb-1 text-sm">Drill types</legend>
			{#each data.stages as stage (stage.n)}
				<div class="mt-2 mb-1 flex items-center gap-2 text-[11px] uppercase tracking-wider text-muted">
					Stage {stage.n} — {stage.title}
					{#if stage.n > s.unlockedStages}<span class="normal-case">· not yet</span>{/if}
				</div>
				{#each stage.types as t (t.value)}
					<label class="flex min-h-[44px] items-start gap-2 py-1">
						<input
							type="checkbox"
							value={t.value}
							checked={s.activeCardTypes.includes(t.value)}
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
							<span class="block text-sm">{t.label}</span>
							<span class="block text-[11px] text-muted">{t.hint}</span>
						</span>
					</label>
				{/each}
			{/each}
		</fieldset>
	</section>

	<section class="rounded-xl border border-line bg-surface p-4">
		<h2 class="mb-1 text-[11px] uppercase tracking-wider text-muted">The path</h2>
		<p class="mb-2 text-xs text-muted">
			Stages open by practice — the Today screen shows what the next one needs. Impatient? Open a
			stage here; the deck grows the moment you save.
		</p>

		<label class="flex min-h-[44px] items-center gap-2">
			<input type="checkbox" bind:checked={s.stageAutoUnlock} class="size-5" />
			<span class="text-sm">Open the next stage automatically when it is earned</span>
		</label>

		{#each data.stages as stage (stage.n)}
			<div class="flex min-h-[44px] items-center gap-2">
				<span class="flex-1 text-sm">
					{stage.n}. {stage.title}
				</span>
				{#if stage.n <= s.unlockedStages}
					<span class="text-xs text-good">open</span>
				{:else}
					<button
						type="button"
						class="rounded-lg border border-line px-3 py-1.5 text-xs text-accent"
						data-testid="open-stage-{stage.n}"
						onclick={() => (s.unlockedStages = stage.n)}>Open now</button
					>
				{/if}
			</div>
		{/each}
	</section>

	<section class="rounded-xl border border-line bg-surface p-4">
		<h2 class="mb-3 text-[11px] uppercase tracking-wider text-muted">Scheduling</h2>

		<label class="mb-3 block">
			<span class="text-sm">Target retention</span>
			<span class="ml-1 text-xs text-muted">%</span>
			<input
				type="number"
				min="70"
				max="98"
				value={Math.round(s.targetRetention * 100)}
				oninput={(e) => (s.targetRetention = Number(e.currentTarget.value) / 100)}
				class="mt-1 min-h-[44px] w-full rounded-lg border border-line bg-surface-2 px-3"
			/>
			<span class="mt-1 block text-xs text-muted">
				Higher means more reviews per day. 90% is the sensible default.
			</span>
		</label>
	</section>

	<button
		type="submit"
		disabled={busy}
		class="min-h-[56px] w-full rounded-xl bg-accent-solid text-base font-semibold text-white disabled:opacity-50"
		data-testid="save-settings">Save</button
	>
</form>

<section class="mt-4 rounded-xl border border-line bg-surface p-4">
	<h2 class="mb-2 text-[11px] uppercase tracking-wider text-muted">Your data</h2>
	<p class="mb-3 text-xs text-muted">
		Everything lives on this device and nowhere else. Nothing is uploaded, so a backup is your
		responsibility — and a new phone needs an export.
	</p>

	<button
		type="button"
		onclick={downloadExport}
		class="flex min-h-[44px] w-full items-center text-sm text-accent underline"
		data-testid="export-link">Export everything as JSON</button
	>

	<button
		type="button"
		onclick={() => fileInput?.click()}
		class="flex min-h-[44px] w-full items-center text-sm text-accent underline"
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
		class="flex min-h-[44px] w-full items-center text-sm text-bad underline"
		data-testid="erase-link">Erase all practice history &amp; settings</button
	>
</section>
