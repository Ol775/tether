#!/bin/bash
# Build the app, launch it against the demo fake-adb for each pane and capture docs/images/<pane>.png.
# Doubles as the launch smoke test: fails if a window doesn't appear within 15 s.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/bundle.sh >/dev/null
mkdir -p docs/images
capture() {  # capture <pane> <output name> [env assignment]
  pane=$1; name=$2
  env ${3:-TETHER_NONE=1} TETHER_PANE=$pane demo/run.sh build/Tether.app/Contents/MacOS/Tether >/dev/null 2>&1 &
  pid=$!
  id=""
  for _ in $(seq 30); do
    sleep 0.5
    id=$(swift scripts/windowid.swift Tether 2>/dev/null || true)
    [[ -n $id ]] && break
  done
  [[ -n $id ]] || { kill "$pid" 2>/dev/null; echo "no window for pane $pane" >&2; exit 1; }
  sleep 2   # let the demo device load
  screencapture -x -o -l "$id" "docs/images/$name.png"
  kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
  echo "captured $name"
}

for pane in overview debloat tweaks apps backups console; do capture "$pane" "$pane"; done
for pane in overview debloat apps; do capture "$pane" "tizen-$pane" TETHER_TIZEN_DEMO=1; done
