# Tether — design (slice B: Samsung Tizen TVs, 2019 onwards)

Adds Samsung Tizen TVs to Tether over network `sdb`. Slice A (Android/Fire OS
over `adb`) is the pattern: restore point first, one engine for every change,
typed errors, curated catalog, guarded console.

## Intent

- **For:** the owner's own Samsung TVs (2019 models and later); private repo.
- **Success:** connect to a TV over the network, see what is installed,
  install a signed app, remove what the firmware allows, and revert.
  Be honest about what a given TV refuses.
- **Not a goal:** rooting, firmware modification, defeating DRM, anything that
  needs an exploit. See "Debloat reality".

## What the research says (sources are forum posts and community guides, not Samsung docs)

- The TV must be in **Developer Mode** with the Mac's IP entered on the TV;
  `sdb` then connects on port **26101**. Some 2023+ models reportedly refuse
  connections even so.
- Installs need a **certificate containing the TV's DUID**. Tizen Studio's
  Device and Certificate Managers do this.
- **Preinstalled apps:** on retail firmware most are marked non-removable over
  `sdb`. Older firmware (~2019–2020) sometimes allows `vd_appuninstall`;
  recent firmware reportedly allows only a few packages. The only
  broad-removal method found needs root, which is out of scope.
  Re-downloads after a Smart Hub reset are reported.

## Debloat reality (what "debloat" means here)

1. **Removable apps** (user-installed, and whatever preloads this TV allows)
   are removed through the same engine and restore point.
2. **Per-TV capability probe:** before offering removal, Tether asks the TV
   which packages it will let `sdb` remove. Anything refused is shown as
   "Locked by Samsung" with the reason, never as a button that fails.
3. **Reversible alternatives** where the TV supports them (deactivating a
   package rather than uninstalling it) are offered only after being verified
   on a real TV (spike 2). Otherwise they do not ship.
4. **Catalog** (same JSON format, `platform: tizen`) records for each preload:
   what it is, which model years allow removal, risk tier, and a `source`.
   Entries start unverified, as in slice A.

Reinstalling a removed *preload* is not promised: Tether keeps the app list
and, for apps it installed itself, the signed `.wgt`. For an app the TV
removed from its own image, "restore" means "Smart Hub will usually offer it
again", and the UI says so.

## Decisions

| Topic | Decision |
|---|---|
| Tooling | **Deviation from "bundle Tizen Studio":** Tether does not redistribute it. I found no statement permitting redistribution, and it is large and Java based. Instead a one-time **"Set up Samsung tools"** step downloads Samsung's official CLI installer from `download.tizen.org` and runs it with the licence shown to the user for acceptance. The result is the same: one app, no manual Tizen Studio work. Veto this if you want a different route |
| Binaries needed | `sdb` and the `tizen` CLI (install, uninstall, certificates), kept under Application Support, never committed |
| Certificates | Samsung certificate creation is the highest risk. **Spike 1** checks whether the `tizen certificate` flow and the certificate extension can be driven without Tizen Studio's GUI and whether a Samsung account sign-in is needed. If not scriptable, Tether opens Samsung's Certificate Manager and guides the user, then imports the result |
| Transport | `SDBRunner` mirrors `ADBRunner` (private process, temp-file output, timeouts, typed errors). Only the second implementation exists now, so shared code is extracted by moving the common process runner, not by inventing a protocol |
| Backup | Per-TV restore point: model, firmware, capability report, installed app list with versions, and the signed `.wgt` for apps Tether installed. No app data |
| Console | Guarded raw `sdb shell`, same allowlist idea. Many TVs disable the shell; the UI then hides it and says why |
| Model years | 2019 onwards. Earlier TVs are not tested and are refused politely |

## Architecture

- `TetherCore` gains a `Tizen` area: `SDBRunner`, `TizenDevice` profile
  (model, year, Tizen version, capabilities), `TizenPackages` parsers,
  `TizenChange` (uninstall, install), `TizenCertificates`, `SamsungTools`
  (download and verify the CLI installer).
- Reuse: `RiskTier`, catalog decoding with a `platform` field, restore-point
  store, `ChangeLog`, `ChangeReport`, the report sheet and confirm sheets.
- A TV appears in the same sidebar; sections show only what the platform
  supports (Overview, Debloat, Apps, Backups, Console; Tweaks only if a safe
  Tizen tweak is verified).
- Pairing sheet for Tizen: steps to enable Developer Mode (Apps → press
  12345 → Developer mode ON, enter this Mac's IP, reboot TV), then connect.
  Tether shows the Mac's current IP to copy.

## Errors

Typed, each with cause and next step: Developer Mode off, wrong host IP
entered on the TV, connection refused (model blocks `sdb`), certificate does
not include this TV's DUID, package locked by Samsung, shell disabled,
tools not installed.

## Testing

- Parsers and capability probe against recorded `sdb` output fixtures.
- A scripted fake `sdb`, as in slice A, drives probe → restore point →
  uninstall → verify → revert with no TV.
- Real-TV checklist per model year. I can write it; only you can run it.

## Spikes (answered before the plan is written)

1. Can Samsung certificates be created and imported without the Tizen Studio
   GUI? Is a Samsung account required?
2. Does this TV support a reversible deactivate, and what exactly does the
   capability report expose? Needs your TV, so this one runs on hardware.

## Non-goals

Rooting, Vega OS, notarisation, app-data backup, TVs before 2019, hiding
Smart Hub ads at network level.

## Delivery

Same repo, same app. README, `docs/setup/samsung-tv.md`, and a Tizen device
checklist. Public identity stays the handle `Ol775` and the noreply email.
