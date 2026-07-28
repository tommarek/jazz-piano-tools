/**
 * Works around an upstream packaging bug in @capacitor-community/sqlite.
 *
 * Its Package.swift asks for capacitor-swift-pm by **branch**:
 *
 *   .package(url: ".../capacitor-swift-pm.git", branch: "8.0.0")
 *
 * while @capacitor/app, @capacitor/preferences and Capacitor's own generated
 * CapApp-SPM ask for it by **version** (`from:` and `exact:`). SwiftPM cannot
 * mix a branch requirement with version requirements for the same package, and
 * rather than reporting the conflict it hangs: `xcodebuild` sits at 0% CPU
 * forever, after printing "Checking out ... capacitor-swift-pm", with no error
 * and no timeout. It cost an afternoon to find, so it is worth automating.
 *
 * Rewriting `branch:` to `from:` makes the graph satisfiable and resolution
 * picks the version the rest of the project already wants.
 *
 * Idempotent, and a no-op once upstream fixes it. Runs from `postinstall`, so a
 * fresh `npm install` cannot quietly reintroduce the hang.
 */

import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const MANIFEST = 'node_modules/@capacitor-community/sqlite/Package.swift';
const BRANCH_DEP =
	/\.package\(url: "https:\/\/github\.com\/ionic-team\/capacitor-swift-pm\.git", branch: "([^"]+)"\)/;

if (!existsSync(MANIFEST)) {
	// Nothing installed yet, or the plugin was removed. Both are fine.
	process.exit(0);
}

const before = readFileSync(MANIFEST, 'utf8');
const match = before.match(BRANCH_DEP);

if (!match) {
	process.exit(0);
}

const after = before.replace(
	BRANCH_DEP,
	`.package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "${match[1]}")`
);
writeFileSync(MANIFEST, after);
console.log(
	`[patch-capacitor-spm] capacitor-swift-pm: branch "${match[1]}" -> from "${match[1]}" ` +
		'(a branch requirement makes SwiftPM hang; see the comment in this script)'
);
