# Tether — design (slice A)

Native macOS app for managing Android and Fire OS devices over network ADB:
backup, debloat, curated tweaks, and app installs. Slice B (Samsung Tizen via
`sdb`) follows; Vega OS later if its tooling allows.

## Intent

- **For:** the owner's own devices; private repo for now.
- **Success:** pair a device over the network, take a restore point, remove
  tracking/bloat packages with plain-English guidance, apply reversible tweaks,
  install apps from a GitHub release or local APK, and revert any change in one
  click.
- **Platform:** macOS 26+, Swift 6.4, SwiftUI, Liquid Glass. Inspiration:
  taste.dev and Emil Kowalski (motion/polish principles, not code).
- **Distribution:** one self-contained `.app`. `adb` is bundled at build time.

## Non-goals (slice A)

Tizen/`sdb`, Vega OS, notarisation, app-data backup, self-updating the app.

## Decisions

| Topic | Decision |
|---|---|
| Build order | Core + Android/Fire OS first, Tizen second |
| `adb` source | Build script downloads official `platform-tools` into the bundle; binaries not committed. Revisit licence if repo goes public |
| Backup | Per-device **restore point**, automatic before any change: package list + per-user state, APKs of packages about to be removed, settings dump (global/secure/system). No `/sdcard` or app-data backup |
| Debloat knowledge | Curated JSON catalog bundled in app, keyed by vendor, risk tiers (Safe/Recommended/Advanced/Expert), description, "breaks X" note. Seeded from community research (check UAD-ng licence before copying data). Refreshable from the repo without an app release |
| Mods | Curated reversible toggles **plus** a guarded raw console |
| Transport abstraction | None until `sdb` lands; extract from working code in slice B |
| Name | Tether (working) |

## Architecture

Local Swift package `TetherCore` holds all logic; the SwiftUI app target is
thin.

- **ADB** — runs bundled `adb` as an async process on a private server port
  (never collides with a system `adb`); typed parsed results; timeouts.
- **Devices** — Bonjour discovery (`_adb-tls-connect`, `_adb-tls-pairing`),
  manual `IP:port` connect, wireless pairing code. Vendor/OS from `getprop`.
- **RestorePoints** — one folder per snapshot: JSON of package states and
  settings, plus pulled APKs. Write is verified before any change proceeds.
- **Catalog** — loads and validates bundled debloat JSON; refresh from repo.
- **Changes** — the only path to mutating commands.
- **Tweaks** — each toggle defines read, set, revert.
- **Installer** — local file or GitHub release (select APK asset, match device
  ABI, `adb install`).
- **Console** — raw commands; confirms destructive verbs; logs everything.

Removal uses `pm uninstall -k --user 0` (reversible via
`cmd package install-existing`); the pulled APK is a fallback.

## Tweaks (initial set)

Animation scales, screen density (DPI), private DNS, Fire TV ad/telemetry
settings, default launcher swap (e.g. Projectivy), screensaver/sleep timeouts,
per-app permission revoke. Each stores its previous value in the restore point.

## UI

Three-column `NavigationSplitView`.

- **Sidebar (glass):** devices with live state; Overview, Debloat, Tweaks,
  Apps, Backups, Console; Add device.
- **Content:** selected section. **Inspector (collapsible):** description, risk
  tier, what breaks, revert history.
- **Liquid Glass on chrome only** (sidebar, toolbar, floating action bar,
  sheets) via `glassEffect`/`GlassEffectContainer`; content rows solid; no
  glass-on-glass.
- **Taste:** one accent colour; tiers are the only other colour (green, blue,
  amber, red) and also carry icon + label; motion < 250 ms with `.smooth` /
  `.snappy`; interruptible; press scale 0.97; in-place number/state
  animation; Reduce Motion honoured.
- **Debloat screen:** searchable, grouped by vendor and risk; Safe
  preselected; Expert behind a toggle; floating bar "Remove N · restore point
  will be saved".
- **Pairing sheet:** device-specific steps (e.g. Fire TV *Settings → My Fire TV
  → Developer Options*), then discovery or IP entry.
- **Empty/error states** state the next step.
- **Accessibility:** full VoiceOver labels, keyboard navigation, no
  colour-only meaning.

## Data flow (any change)

select → preview diff → confirm → take and verify restore point → apply each
command → re-read device state to confirm → log. On failure: stop, report
exactly what changed, offer one-click revert.

## Errors

Typed: unauthorised, offline, no-permission, package-protected, adb-missing.
Each has a plain-English cause and next step. Commands time out. State is
re-read on reconnect, so a mid-operation unplug never leaves it ambiguous.

## Testing

- Unit: output parsers, catalog schema validation, restore-point round-trip,
  revert planner — against recorded `adb` output fixtures.
- Fake `adb` stub binary drives the full change pipeline end to end with no
  device.
- Manual real-device checklist per vendor.
- A few UI smoke tests; scripted screenshots for the README.

## Delivery

- Xcode app project + `TetherCore` package; build script fetches
  `platform-tools` into the bundle.
- Ad-hoc signed; README documents the first-run Gatekeeper step.
- Private GitHub repo `Ol775/tether`: README, `docs/` (architecture, safety
  model, catalog format, Fire TV and Android setup guides), screenshots.
- Public-facing identity is the handle `Ol775` and the GitHub noreply email
  only.
