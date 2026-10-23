#!/bin/bash
# Fetch Google's platform-tools (adb) into vendor/. Pinned version; sha256 is recorded on
# first fetch in scripts/platform-tools.sha256 and enforced afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=37.0.0
ZIP="platform-tools_r$VERSION-darwin.zip"
SUMFILE=scripts/platform-tools.sha256
mkdir -p vendor
[[ -x vendor/platform-tools/adb ]] && { echo "adb already in vendor/"; exit 0; }
curl -fsSL "https://dl.google.com/android/repository/$ZIP" -o "vendor/$ZIP"
actual=$(shasum -a 256 "vendor/$ZIP" | cut -d' ' -f1)
if [[ -f $SUMFILE ]]; then
  [[ $(cut -d' ' -f1 "$SUMFILE") == "$actual" ]] || { echo "checksum mismatch for $ZIP" >&2; rm "vendor/$ZIP"; exit 1; }
else
  echo "$actual  $ZIP" > "$SUMFILE"; echo "recorded $SUMFILE (commit it)"
fi
unzip -qo "vendor/$ZIP" -d vendor
rm "vendor/$ZIP"
