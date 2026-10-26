#!/bin/zsh
# Publishes the version in VERSION: builds the app, zips it, signs the zip with the release key and creates the GitHub release
# (zip + .sha256 + .sig2). Run after bumping VERSION and CHANGELOG.md, committing and pushing (see RELEASING.md).
# Usage: ./release.sh [--dry-run]   --dry-run runs every check and builds and signs the zip, but publishes nothing.
# The signing key (never committed, back it up!) lives at ~/.config/tether/signing.key; its public half is built into the app.
set -eo pipefail
cd "$(dirname "$0")"
ver=$(cat VERSION)
dry=0; [ "$1" = "--dry-run" ] && dry=1
changes=$(awk -v v="## $ver " 'index($0, v) == 1 {on = 1; next} /^## / {on = 0} on' CHANGELOG.md | sed '/^$/d')
[ -n "$changes" ] || { echo "No CHANGELOG entry for $ver."; exit 1; }
note="$changes

> **Beta: use at your own risk.** Tether changes settings and removes apps on your devices. See the [README](https://github.com/Ol775/tether#readme).

**Install or update:** the app updates itself, or download \`Tether-$ver.zip\`, unzip, move Tether to Applications and right-click → Open the first time. Every zip is signed with the offline release key and has a SHA-256 checksum; see [how updates are verified](https://github.com/Ol775/tether/blob/main/SECURITY.md#how-updates-are-trusted)."
key="${SIGNING_KEY:-$HOME/.config/tether/signing.key}"
[ -f "$key" ] || { echo "No signing key at $key. Releases must be signed (see scripts/sign-tool.swift)."; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit your changes first."; exit 1; }
git fetch -q origin main; [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "Push main first."; exit 1; }
# A published v$ver blocks (bump VERSION); a CI-created draft is finalized below; none → create fresh.
state=$(gh release view "v$ver" --repo Ol775/tether --json isDraft -q .isDraft 2>/dev/null) || state="none"
[ "$state" = "false" ] && { echo "v$ver is already released. Bump VERSION."; exit 1; }
mkdir -p build
echo "Running the test suite (log: build/release-tests.log)…"
if swift test --disable-sandbox 2>&1 | tee build/release-tests.log; then
  echo "Test suite passed. Building the release…"
else
  echo "The test suite failed. Full output is saved in build/release-tests.log."
  exit 1
fi
mkdir -p build dist && swiftc -O scripts/sign-tool.swift -o build/sign-tool 2>/dev/null
pub=$(build/sign-tool public "$key")
[ "$pub" = "$(grep -o 'publicKey = "[^"]*"' Sources/TetherCore/Update/Updater.swift | cut -d'"' -f2)" ] || { echo "The signing key doesn't match the public key built into the app."; exit 1; }
./scripts/bundle.sh >/dev/null 2>&1
[ "$(defaults read "$PWD/build/Tether.app/Contents/Info" CFBundleShortVersionString)" = "$ver" ] || { echo "The built app isn't version $ver."; exit 1; }
zip="dist/Tether-$ver.zip"
rm -f "$zip"; ditto -c -k --keepParent build/Tether.app "$zip"
shasum -a 256 "$zip" | awk '{print $1"  Tether-'"$ver"'.zip"}' > "$zip.sha256"
build/sign-tool sign-update "$key" "$zip" "$ver" > "$zip.sig2"
build/sign-tool verify "$pub" "$zip" "$zip.sig2" "$ver" >/dev/null || { echo "The signature doesn't verify."; exit 1; }
[ "$dry" = 1 ] && { echo "Dry run OK: v$ver would be published; zip signed and signature verified ($(du -h "$zip" | cut -f1))."; exit 0; }
if [ "$state" = "true" ]; then  # finalize the draft CI created on the version-bump push
  gh release upload "v$ver" "$zip" "$zip.sha256" "$zip.sig2" --repo Ol775/tether --clobber
  gh release edit "v$ver" --repo Ol775/tether --draft=false --latest --title "v$ver (beta)" --notes "$note"
else
  gh release create "v$ver" "$zip" "$zip.sha256" "$zip.sig2" --repo Ol775/tether --title "v$ver (beta)" --notes "$note" --latest
fi
echo "Released v$ver"
