#!/bin/bash
# Launch the built app against a scratch copy of the demo fake-adb state (never touches real data).
set -euo pipefail
cd "$(dirname "$0")/.."
SCRATCH=$(mktemp -d)
cp -R demo/state "$SCRATCH/state"
mkdir -p "$SCRATCH/support"
export TETHER_ADB="$PWD/Tests/TetherCoreTests/Fixtures/fake-adb"
export FAKE_ADB_DIR="$SCRATCH/state"
export TETHER_SUPPORT="$SCRATCH/support"
exec "${1:-build/Tether.app/Contents/MacOS/Tether}"
