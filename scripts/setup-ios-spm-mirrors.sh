#!/bin/bash
#
# Works around a SwiftPM defect that makes iOS builds hang forever.
#
# THE PROBLEM
# -----------
# Capacitor 8's iOS integration ships as *binary* SPM targets — prebuilt
# .xcframework zips fetched from GitHub Releases. On some machines SwiftPM's
# artifact downloader never completes: `xcodebuild` prints
#
#     Downloading binary artifact https://.../Capacitor.xcframework.zip
#
# and then sits at 0% CPU forever, with no error, no timeout and no build.
# It is not the network — curl and URLSession both fetch the same URL in under
# a second, and a one-target test package reproduces the hang on its own.
#
# THE FIX
# -------
# Clone the two offending packages locally, download their xcframeworks with
# curl (which works), vendor them into the clones, rewrite the binary targets
# from `url:`+`checksum:` to a local `path:`, and point SwiftPM at the clones
# with a mirror. Nothing is left to download, so nothing can hang.
#
# Run this once. It is idempotent. If SwiftPM's downloader is healthy on your
# machine, you do not need it — delete ~/.spm-local-mirrors and the two
# mirrors.json files and everything resolves from upstream as normal.
#
set -euo pipefail

MIRRORS="${SPM_MIRROR_DIR:-$HOME/.spm-local-mirrors}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_SPM="$HERE/ios/App/App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"

# Versions must match what the manifests ask for. `npx cap sync ios` regenerates
# CapApp-SPM/Package.swift from the installed @capacitor/core, so if you upgrade
# Capacitor, bump CAPACITOR_VERSION to match and re-run.
CAPACITOR_VERSION="${CAPACITOR_VERSION:-8.4.2}"
SQLCIPHER_VERSION="${SQLCIPHER_VERSION:-4.17.0}"

vendor() {
	local name="$1" repo="$2" version="$3"; shift 3
	local frameworks=("$@")
	local dir="$MIRRORS/$name"

	echo "==> $name @ $version"
	rm -rf "$dir"
	git clone -q --depth 1 --branch "$version" "$repo" "$dir"
	rm -rf "$dir/.git"
	mkdir -p "$dir/Frameworks"

	local base="${repo%.git}"
	for fw in "${frameworks[@]}"; do
		local zip; zip="$(mktemp -t "$fw").zip"
		# -f so an HTTP error is an error rather than a saved error page.
		curl -fsSL -o "$zip" "$base/releases/download/$version/$fw.xcframework.zip"
		unzip -q -o "$zip" -d "$dir/Frameworks/"
		rm -f "$zip"
		# Rewrite the remote binary target to a local one.
		python3 - "$dir/Package.swift" "$fw" <<-'PY'
			import re, sys, pathlib
			path, name = sys.argv[1], sys.argv[2]
			p = pathlib.Path(path); s = p.read_text()
			pattern = (r'\.binaryTarget\(\s*name:\s*"%s",\s*url:\s*"[^"]+",\s*'
			           r'checksum:\s*"[^"]+"\s*\)' % re.escape(name))
			replacement = '.binaryTarget(name: "%s", path: "Frameworks/%s.xcframework")' % (name, name)
			new, n = re.subn(pattern, replacement, s, flags=re.S)
			if n == 0:
			    sys.exit(f"could not rewrite binary target {name} in {path}")
			p.write_text(new)
		PY
	done

	# Upstream .gitignore excludes *.xcframework, which would silently drop the
	# very files being vendored.
	[ -f "$dir/.gitignore" ] && sed -i '' '/xcframework/d;/^\*\.zip$/d' "$dir/.gitignore"

	git -C "$dir" init -q
	git -C "$dir" add -A -f
	git -C "$dir" -c user.email=mirror@local -c user.name=mirror commit -qm "vendored xcframeworks"
	git -C "$dir" tag "$version"
	echo "    $(git -C "$dir" ls-files Frameworks | wc -l | tr -d ' ') framework files vendored"
}

mkdir -p "$MIRRORS"
vendor capacitor-swift-pm https://github.com/ionic-team/capacitor-swift-pm.git \
	"$CAPACITOR_VERSION" Capacitor Cordova
vendor SQLCipher.swift https://github.com/sqlcipher/SQLCipher.swift.git \
	"$SQLCIPHER_VERSION" SQLCipher

# xcodebuild reads mirrors from the workspace, not from the package directory.
mkdir -p "$WORKSPACE_SPM" "$HERE/ios/App/CapApp-SPM/.swiftpm/configuration"
cat > "$WORKSPACE_SPM/mirrors.json" <<JSON
{
  "object" : [
    {
      "mirror" : "file://$MIRRORS/SQLCipher.swift",
      "original" : "https://github.com/sqlcipher/SQLCipher.swift.git"
    },
    {
      "mirror" : "file://$MIRRORS/capacitor-swift-pm",
      "original" : "https://github.com/ionic-team/capacitor-swift-pm.git"
    }
  ],
  "version" : 1
}
JSON
cp "$WORKSPACE_SPM/mirrors.json" "$HERE/ios/App/CapApp-SPM/.swiftpm/configuration/mirrors.json"

# A stale Package.resolved and SwiftPM's fingerprint database both remember the
# upstream revisions and will refuse the mirrors.
rm -f "$WORKSPACE_SPM/Package.resolved" "$HERE/ios/App/CapApp-SPM/Package.resolved"
rm -rf "$HOME/Library/org.swift.swiftpm/security" "$HOME/.swiftpm/security"

echo
echo "Mirrors ready in $MIRRORS"
echo "Build with: cd ios/App && xcodebuild -project App.xcodeproj -scheme App \\"
echo "              -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build"
