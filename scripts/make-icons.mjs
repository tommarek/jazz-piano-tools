/**
 * Generates every icon the app needs, from source.
 *
 * Hand-rolled rather than pulled from a rasteriser: the artwork is rectangles,
 * so a pixel loop plus zlib is less machinery than a dependency, and the output
 * is checked in.
 *
 * The design is a guide-tone pair — a keyboard with exactly two keys lit, the
 * 3rd and the 7th, which is what the deck drills. Five white keys rather than a
 * full octave, because seven are indistinguishable mush at 40px, and two lit
 * keys say what the app is about at any size.
 *
 * Everything is drawn at 1024 and left for the asset pipeline to downscale with
 * proper resampling; this renderer has no anti-aliasing of its own.
 *
 *   node scripts/make-icons.mjs
 */
import { deflateSync } from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';

// The shell's own colours, and they have to stay the shell's own: the splash is
// painted before the web view has a stylesheet, so a background that is not
// --color-bg to the byte is a colour flash on every launch. The keys carry the
// materials Keyboard.svelte uses, which are deliberately not tokens.
const BG = [19, 17, 15, 255]; // --color-bg #13110f
const WHITE = [236, 228, 214, 255]; // ivory, as the keyboard draws it
const BLACK = [16, 14, 12, 255]; // ebony, likewise
const ACCENT = [215, 166, 79, 255]; // --color-brass #d7a64f
const GAP = [19, 17, 15, 255];
const NONE = [0, 0, 0, 0];

// ---------------------------------------------------------------------------
// Minimal PNG writer (RGBA)
// ---------------------------------------------------------------------------

const CRC_TABLE = (() => {
	const table = new Int32Array(256);
	for (let n = 0; n < 256; n++) {
		let c = n;
		for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
		table[n] = c;
	}
	return table;
})();

function crc32(buf) {
	let crc = 0xffffffff;
	for (const b of buf) crc = CRC_TABLE[(crc ^ b) & 0xff] ^ (crc >>> 8);
	return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
	const len = Buffer.alloc(4);
	len.writeUInt32BE(data.length);
	const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
	const crc = Buffer.alloc(4);
	crc.writeUInt32BE(crc32(body));
	return Buffer.concat([len, body, crc]);
}

function png(width, height, pixels) {
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(width, 0);
	ihdr.writeUInt32BE(height, 4);
	ihdr[8] = 8; // bit depth
	ihdr[9] = 6; // truecolour with alpha
	const stride = width * 4 + 1;
	const raw = Buffer.alloc(height * stride);
	for (let y = 0; y < height; y++) {
		raw[y * stride] = 0; // filter: none
		for (let x = 0; x < width; x++) {
			const [r, g, b, a] = pixels(x, y);
			const off = y * stride + 1 + x * 4;
			raw[off] = r;
			raw[off + 1] = g;
			raw[off + 2] = b;
			raw[off + 3] = a;
		}
	}
	return Buffer.concat([
		Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
		chunk('IHDR', ihdr),
		chunk('IDAT', deflateSync(raw, { level: 9 })),
		chunk('IEND', Buffer.alloc(0))
	]);
}

// ---------------------------------------------------------------------------
// The artwork
// ---------------------------------------------------------------------------

const WHITE_KEYS = 5;
/** Black keys sit after white keys 0, 1 and 3 — C♯, D♯, F♯. */
const BLACK_SLOTS = [1, 2, 4];
/** The guide tones of a ii chord: the C and F of Dm7, its ♭7 and ♭3. */
const LIT = [0, 3];

/**
 * Draws the keyboard centred in a `size` canvas.
 *
 * `scale` is the keyboard's width as a fraction of the canvas. Adaptive icons
 * need a much smaller one: Android masks the outer third away, and an icon
 * drawn to the edge comes back with its corners bitten off.
 */
function keyboard({ size, scale, background }) {
	const kbWidth = size * scale;
	const kbHeight = kbWidth * 0.72;
	const left = (size - kbWidth) / 2;
	const top = (size - kbHeight) / 2;
	const whiteWidth = kbWidth / WHITE_KEYS;
	const blackWidth = whiteWidth * 0.58;
	const blackHeight = kbHeight * 0.62;
	const gap = Math.max(1, size * 0.004);
	const radius = kbHeight * 0.08;

	return (x, y) => {
		if (x < left || x >= left + kbWidth || y < top || y >= top + kbHeight) return background;

		// Round the bottom corners of the whole keybed.
		const fromBottom = top + kbHeight - y;
		if (fromBottom < radius) {
			const dxLeft = x - (left + radius);
			const dxRight = x - (left + kbWidth - radius);
			const dy = radius - fromBottom;
			if (dxLeft < 0 && dxLeft * dxLeft + dy * dy > radius * radius) return background;
			if (dxRight > 0 && dxRight * dxRight + dy * dy > radius * radius) return background;
		}

		for (const slot of BLACK_SLOTS) {
			const cx = left + slot * whiteWidth;
			if (y < top + blackHeight && x >= cx - blackWidth / 2 && x < cx + blackWidth / 2) {
				return BLACK;
			}
		}

		const index = Math.floor((x - left) / whiteWidth);
		// A hairline between white keys, so they read as separate keys.
		if ((x - left) % whiteWidth < gap && index > 0) return GAP;
		return LIT.includes(index) ? ACCENT : WHITE;
	};
}

const out = resolve(process.cwd(), 'assets');
mkdirSync(out, { recursive: true });
const staticDir = resolve(process.cwd(), 'static');
mkdirSync(staticDir, { recursive: true });

// Store and home-screen icon: full bleed on the app's background colour.
const ICON = 1024;
writeFileSync(
	resolve(out, 'icon.png'),
	png(ICON, ICON, keyboard({ size: ICON, scale: 0.78, background: BG }))
);

// Android adaptive icon: foreground on transparency, kept well inside the mask.
writeFileSync(
	resolve(out, 'icon-foreground.png'),
	png(ICON, ICON, keyboard({ size: ICON, scale: 0.52, background: NONE }))
);
writeFileSync(resolve(out, 'icon-background.png'), png(ICON, ICON, () => BG));

// Splash: the same mark, small, on the same background — so launching the app
// does not flash a different colour before the UI arrives.
const SPLASH = 2732;
const splash = keyboard({ size: SPLASH, scale: 0.22, background: BG });
writeFileSync(resolve(out, 'splash.png'), png(SPLASH, SPLASH, splash));
writeFileSync(resolve(out, 'splash-dark.png'), png(SPLASH, SPLASH, splash));

// PWA icons, generated at their final sizes rather than downscaled.
for (const size of [180, 192, 512]) {
	writeFileSync(
		resolve(staticDir, `icon-${size}.png`),
		png(size, size, keyboard({ size, scale: 0.78, background: BG }))
	);
}

console.log('wrote assets/{icon,icon-foreground,icon-background,splash,splash-dark}.png');
console.log('wrote static/icon-{180,192,512}.png');
console.log('now run: npx capacitor-assets generate');
