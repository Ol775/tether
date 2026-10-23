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
if [[ ${TETHER_TIZEN_DEMO:-} == 1 ]]; then
  # Samsung TV demo: no adb devices, a scripted sdb and tizen CLI inside a fake tools folder.
  mkdir -p "$SCRATCH/adbstate" && : > "$SCRATCH/adbstate/devices.txt"
  export FAKE_ADB_DIR="$SCRATCH/adbstate"
  cp -R demo/state-tizen "$SCRATCH/sdbstate"
  TOOLS="$SCRATCH/samsung/tizen-studio/tools"
  mkdir -p "$TOOLS/ide/bin"
  printf '#!/bin/bash\nexport FAKE_SDB_DIR="%s"\nexec "%s" "$@"\n' "$SCRATCH/sdbstate" "$PWD/Tests/TetherCoreTests/Fixtures/fake-sdb" > "$TOOLS/sdb"
  printf '#!/bin/bash\necho "profile: Demo (active)"\necho "  duid: DEMODUID0123456789"\n' > "$TOOLS/ide/bin/tizen"
  chmod +x "$TOOLS/sdb" "$TOOLS/ide/bin/tizen"
  cp demo/state-tizen/tizen-locked.json "$SCRATCH/support/tizen-locked.json"
  export TETHER_SAMSUNG_HOME="$SCRATCH/samsung"
fi
exec "${1:-build/Tether.app/Contents/MacOS/Tether}"
