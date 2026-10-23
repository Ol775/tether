# Tether Slice A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A self-contained macOS app that pairs with Android/Fire OS devices over network ADB, takes restore points, debloats from a curated catalog, applies reversible tweaks, installs apps from GitHub or file, and reverts any change.

**Architecture:** SwiftPM package. `TetherCore` (all logic, no UI) wraps a bundled `adb` on a private server port; every mutation goes through `ChangeEngine`, which snapshots first. `Tether` is a thin SwiftUI executable; `scripts/bundle.sh` assembles the `.app`. A scripted `fake-adb` drives tests and screenshots without a device.

**Tech Stack:** Swift 6.4 (strict concurrency), SwiftUI Liquid Glass, Swift Testing, Network.framework (Bonjour), bash scripts, `gh`.

**Spec:** `docs/superpowers/specs/2026-10-23-tether-design.md`

**Deviation from spec (veto if unwanted):** SwiftPM + `bundle.sh` instead of an Xcode project (Xcode still opens `Package.swift`); UI smoke tests become a launch-and-screenshot script because SwiftPM has no XCUITest.

## Global Constraints

- macOS 26+ (`.macOS(.v26)`); Swift 6 language mode.
- Liquid Glass (`glassEffect`, `GlassEffectContainer`) on chrome only: sidebar, toolbar, floating action bar, sheets. Content rows solid. No glass-on-glass.
- One accent colour; risk tiers Safe=green, Recommended=blue, Advanced=amber, Expert=red, each with icon + label.
- Motion < 250 ms (`.smooth`/`.snappy`), interruptible, press scale 0.97, Reduce Motion honoured.
- `adb` runs on a private server port (`-P 5038`-style, not 5037); binaries never committed.
- Removal is `pm uninstall -k --user 0`; revert is `cmd package install-existing --user 0 <pkg>`, pulled APK is fallback.
- All mutating commands go through `ChangeEngine`. No restore point verified → no change.
- Public identity: handle `Ol775` and GitHub noreply email only.
- Restore point = package states, APKs of packages to remove, global/secure/system settings dump. No `/sdcard`, no app data.

## Review Focus

1. Device goes offline mid-apply → report lists applied vs pending, state re-read on reconnect (Task 6).
2. Console command hides a destructive verb behind `;`, `&&`, `|`, `$( )`, backticks (Task 9).
3. Package names reach the remote shell (adb joins args) → names validated against a strict regex, hostile names rejected (Tasks 2, 6).
4. Two devices attached → every command carries `-s <serial>`; revert refuses a restore point from another serial (Tasks 1, 6).
5. GitHub release has no APK, several ABIs, only universal, is draft/prerelease, or is rate-limited (Task 8).

## File Structure

```
Package.swift, .gitignore
scripts/{fetch-platform-tools,bundle,screenshots}.sh
Sources/TetherCore/
  ADB/{ADBRunner,ADBError,Parsers,PackageName}.swift
  Devices/{DeviceProfile,DeviceManager,Discovery}.swift
  Restore/{RestorePoint,RestorePointStore}.swift
  Catalog/{Catalog,CatalogStore}.swift   Resources/catalog.json
  Changes/{Change,ChangeEngine,RevertPlanner,ChangeLog}.swift
  Tweaks/{Tweak,TweakLibrary}.swift
  Install/{GitHubRelease,Installer}.swift
  Console/ConsoleGuard.swift
Sources/Tether/  App.swift, Theme.swift, AppModel.swift, Views/*.swift
Tests/TetherCoreTests/  *Tests.swift, Fixtures/{fake-adb,*.txt,*.json}
docs/  architecture.md safety-model.md catalog-format.md device-checklist.md setup/{fire-tv,android}.md
```

### Task 1: Scaffold, fake-adb, ADBRunner

**Files:** Create `Package.swift`, `.gitignore` (`vendor/`, `build/`, `.build/`), `scripts/fetch-platform-tools.sh`, `scripts/bundle.sh`, `ADB/ADBRunner.swift`, `ADB/ADBError.swift`, `Tests/TetherCoreTests/Fixtures/fake-adb`, `ADBRunnerTests.swift`.

**Interfaces:**
- Produces: `actor ADBRunner { init(executable: URL, port: Int = 5038); func run(_ args: [String], serial: String? = nil, timeout: Duration = .seconds(15)) async throws -> String }`
- Produces: `enum ADBError: Error, Equatable { case adbMissing, timeout, unauthorized, offline, noPermission(String), commandFailed(code: Int32, stderr: String) }` with `var advice: String` (plain-English next step).
- Produces: `fake-adb` contract (bash, state in `$FAKE_ADB_DIR`): handles `-P`, `-s`, `devices -l`, `connect`, `pair`, `shell getprop|pm list packages [-u|-d]|pm path|pm uninstall -k --user 0|cmd package install-existing|settings list/get/put/delete|wm density`, `pull`, `install -r`; appends every call to `calls.log`; `FAKE_ADB_FAIL_AFTER=n` makes call n+1 print `error: device offline` and exit 1; mutating calls update the state files.

- [ ] **Step 1:** Write `ADBRunnerTests`: `passesPortAndSerial` (calls.log line starts `-P 5038 -s 192.168.1.5:5555`), `timesOut` (fake sleeps, expects `.timeout`), `mapsUnauthorized` (stderr `device unauthorized` → `.unauthorized`), `missingBinary` (`.adbMissing`).
- [ ] **Step 2:** `swift test --filter ADBRunnerTests` → FAIL (no package).
- [ ] **Step 3:** Create the package (targets `TetherCore` with `resources: [.process("Resources")]`, `Tether`, `TetherCoreTests` with `resources: [.copy("Fixtures")]`), `fake-adb`, `ADBRunner` (`Process` + `withTaskCancellation`/timeout kill; stderr mapping to `ADBError`). `fetch-platform-tools.sh`: download a pinned `platform-tools_rXX-darwin.zip` from `dl.google.com`, verify against `scripts/platform-tools.sha256` (recorded on first fetch, committed), unzip `adb` to `vendor/`. `bundle.sh`: release build → `build/Tether.app` (Info.plist, copy `adb` into `Contents/Resources/`, ad-hoc `codesign --force --deep -s -`).
- [ ] **Step 4:** `swift test --filter ADBRunnerTests` → PASS; `./scripts/fetch-platform-tools.sh && ./scripts/bundle.sh` produces a signed `.app` with `adb` inside. Commit `feat: scaffold package, fake adb, ADBRunner`.

### Task 2: Parsers and package-name validation

**Files:** Create `ADB/Parsers.swift`, `ADB/PackageName.swift`, `Devices/DeviceProfile.swift`, `ParsersTests.swift`, fixtures (`devices-l.txt`, `getprop-firetv.txt`, `getprop-pixel.txt`, `packages-*.txt`, `settings-global.txt`).

**Interfaces:**
- Produces: `struct PackageName: Hashable, Codable, Sendable { init?(_ raw: String); let value: String }` — regex `^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$`; the only way package names reach a command.
- Produces: `enum PackageState: String, Codable { case enabled, disabled, removedForUser }`; `struct PackageSnapshot: Codable, Hashable { let name: PackageName; let state: PackageState }`.
- Produces: `enum Platform: String, Codable { case android, fireOS }`; `struct DeviceProfile: Codable, Equatable, Sendable { serial, vendor (lowercased manufacturer), model, androidVersion, sdk: Int, abis: [String], platform }`.
- Produces: `Parsers.devices(_:) -> [(serial: String, state: String, model: String?)]`, `Parsers.profile(serial:getprop:) -> DeviceProfile` (Fire OS when manufacturer is `amazon`), `Parsers.packages(all:installed:disabled:) -> [PackageSnapshot]`, `Parsers.settings(_:) -> [String: String]`.

- [ ] **Step 1:** Tests: `devicesParsesIPSerialAndModel`, `profileDetectsFireOS`, `profileDetectsPixelAsAndroid`, `packagesDerivesRemovedForUser` (in `all`, not in `installed` → `.removedForUser`), `settingsHandlesEqualsInValue`, `packageNameRejectsHostile` (`com.a;rm -rf /`, `$(id)`, empty, `com..x`, `x` all nil), `packageNameAcceptsReal` (`com.amazon.recess`).
- [ ] **Step 2:** `swift test --filter ParsersTests` → FAIL.
- [ ] **Step 3:** Implement the signatures above; ignore blank/garbage lines rather than throwing.
- [ ] **Step 4:** PASS. Commit `feat: adb output parsers and package-name validation`.

### Task 3: Devices — connect, pair, discover, profile

**Files:** Create `Devices/DeviceManager.swift`, `Devices/Discovery.swift`, `DeviceManagerTests.swift`.

**Interfaces:**
- Consumes: `ADBRunner`, `Parsers`, `DeviceProfile`.
- Produces: `actor DeviceManager { init(adb: ADBRunner); func connect(host: String, port: Int = 5555) async throws; func pair(host: String, port: Int, code: String) async throws; func disconnect(serial: String) async throws; func devices() async throws -> [DeviceProfile]; func profile(serial: String) async throws -> DeviceProfile }` — `profile` issues `-s serial` getprop calls.
- Produces: `struct DiscoveredEndpoint: Hashable { host: String; port: Int; kind: .connect | .pairing; name: String }`; `enum Discovery { static func stream() -> AsyncStream<DiscoveredEndpoint> }` over `NWBrowser` for `_adb-tls-connect._tcp` and `_adb-tls-pairing._tcp`.

- [ ] **Step 1:** Tests: `connectSucceeds`, `connectUnauthorizedThrows` (fake prints `failed to authenticate`), `devicesReturnsProfilesWithSerialQualifiedCalls` (two devices → every `getprop` call in `calls.log` has `-s`), `rejectsBadHost` (host with spaces/`;`).
- [ ] **Step 2:** FAIL. **Step 3:** Implement; validate host with `NWEndpoint.Host`/IP-or-hostname regex; `Discovery` is manual-tested (checklist). **Step 4:** PASS. Commit `feat: device connect, pairing, discovery`.

### Task 4: RestorePoints

**Files:** Create `Restore/RestorePoint.swift`, `Restore/RestorePointStore.swift`, `RestorePointStoreTests.swift`.

**Interfaces:**
- Produces: `struct RestorePoint: Codable, Identifiable { id: UUID, createdAt: Date, reason: String, profile: DeviceProfile, packages: [PackageSnapshot], settings: [String: [String: String]] /* global|secure|system */, apks: [String: [String]] /* package → relative paths */, density: Int? , home: String? }`
- Produces: `actor RestorePointStore { init(root: URL, adb: ADBRunner); func create(device: DeviceProfile, reason: String, pullAPKsFor: [PackageName]) async throws -> RestorePoint; func list() throws -> [RestorePoint]; func load(_ id: UUID) throws -> RestorePoint; func apkURLs(_ rp: RestorePoint, for: PackageName) -> [URL] }` — `create` writes `<root>/<id>/restore.json` + `apks/`, then re-reads it and checks every APK exists and is non-empty, else throws `RestoreError.unverified`.

- [ ] **Step 1:** Tests: `roundTripsJSON`, `pullsSplitAPKs` (fake `pm path` returns 2 paths → 2 files), `failsWhenAPKMissing` (fake pull yields empty → `.unverified`, folder removed), `listsNewestFirst`.
- [ ] **Step 2–4:** FAIL → implement (`pm list packages` ×3, `settings list` ×3, `wm density`, `pm path`, `pull`) → PASS. Commit `feat: verified restore points`.

### Task 5: Catalog

**Files:** Create `Catalog/Catalog.swift`, `Catalog/CatalogStore.swift`, `Resources/catalog.json`, `CatalogTests.swift`; docs `docs/catalog-format.md`.

**Interfaces:**
- Produces: `enum RiskTier: String, Codable, CaseIterable { safe, recommended, advanced, expert }`; `struct CatalogEntry: Codable, Identifiable { package: PackageName, vendors: [String] /* lowercase, "*" = any */, platforms: [Platform]?, tier, title, description, breaks: String? }`.
- Produces: `struct Catalog { static func decode(_ data: Data) throws -> Catalog /* validates */; func entries(for: DeviceProfile, installed: Set<PackageName>) -> [CatalogEntry] }` — validation rejects duplicate package+vendor, empty title/description, `expert`/`advanced` without `breaks`.
- Produces: `struct CatalogStore { init(overrideDir: URL); func load() throws -> Catalog /* override file else bundled */; func refresh(from: URL) async throws -> Bool /* false on 404, validates before replacing */ }`.

- [ ] **Step 1:** Tests: `rejectsDuplicates`, `rejectsAdvancedWithoutBreaks`, `filtersByVendorAndInstalled` (entry for an absent package is omitted), `refreshKeepsOldOnInvalid`, `bundledCatalogIsValid`.
- [ ] **Step 2–3:** FAIL → implement; seed `catalog.json` only with package names verified on a real device or in UAD-ng (licence checked first; record the source per entry in `docs/catalog-format.md`).
- [ ] **Step 4:** PASS. Commit `feat: validated debloat catalog`.

### Task 6: Changes — engine, revert, log

**Files:** Create `Changes/{Change,ChangeEngine,RevertPlanner,ChangeLog}.swift`, `ChangeEngineTests.swift`.

**Interfaces:**
- Produces: `enum Change: Codable, Hashable { removePackage(PackageName), restorePackage(PackageName), setSetting(ns: String, key: String, value: String), deleteSetting(ns: String, key: String), setDensity(Int?), setHome(String?), revokePermission(PackageName, String) }` — `ns` limited to `global|secure|system`.
- Produces: `struct ChangeReport { restorePoint: RestorePoint; applied: [Change]; failed: (Change, ADBError)?; pending: [Change]; verified: Bool }`.
- Produces: `actor ChangeEngine { init(adb: ADBRunner, store: RestorePointStore, log: ChangeLog); func apply(_ changes: [Change], on: DeviceProfile, reason: String) async throws -> ChangeReport; func revert(_ rp: RestorePoint, on: DeviceProfile) async throws -> ChangeReport }`; `enum RevertPlanner { static func plan(_ rp: RestorePoint, current: [PackageSnapshot], currentSettings: [String:[String:String]]) -> [Change] }`; `actor ChangeLog { init(file: URL); func append(_ line: String) }` (JSONL, ISO timestamp, serial, command, result).
- `apply` order: create restore point (APKs for `removePackage` items) → run each change → stop on first failure → re-read packages/settings → set `verified`. `revert` throws `ChangeError.wrongDevice` when serials differ.

- [ ] **Step 1:** Tests: `removesThenRevertsToIdenticalState`, `restorePointWrittenBeforeFirstMutation` (calls.log order), `stopsOnOfflineMidApply` (`FAIL_AFTER=3` → `applied.count == 2`, `pending` listed, no throw), `refusesHostileNames` (`PackageName` can't be built; engine has no string overload), `revertDeletesSettingAbsentBefore`, `revertRefusesOtherDevice`, `usesSerialOnEveryCall`.
- [ ] **Step 2–4:** FAIL → implement (`pm uninstall -k --user 0`, `cmd package install-existing --user 0`, fall back to `adb install-existing`-less path: `install` the pulled APK(s); `settings put/delete`, `wm density N|reset`) → PASS. Commit `feat: change engine with restore, verify and revert`.

### Task 7: Tweaks

**Files:** Create `Tweaks/Tweak.swift`, `Tweaks/TweakLibrary.swift`, `TweakTests.swift`.

**Interfaces:**
- Consumes: `Change`, `DeviceProfile`, `ADBRunner`.
- Produces: `struct Tweak: Identifiable { id: String, title, summary: String, platforms: [Platform], options: [TweakOption] }`, `struct TweakOption { label: String; changes: [Change] }`; `TweakLibrary.all: [Tweak]`; `func currentOption(for: Tweak, settings: [String:[String:String]], density: Int?) -> TweakOption?`.
- Initial set: animation scales (3 `global` keys: off/0.5×/1×), screen density, private DNS (`private_dns_mode`/`private_dns_specifier`), screen-off timeout, screensaver, default launcher, per-app permission revoke, Fire TV ad/telemetry settings. Fire TV keys are unverified until the device checklist run; mark them `platforms: [.fireOS]` and flag in `docs/device-checklist.md`.

- [ ] **Step 1:** Tests: `animationOffProducesThreeSettings`, `currentOptionMatchesAppliedValues`, `everyTweakOptionRevertsViaRestorePoint` (apply via engine, revert, settings equal), `fireOSOnlyTweaksHiddenOnPixel`.
- [ ] **Step 2–4:** FAIL → implement → PASS. Commit `feat: curated reversible tweaks`.

### Task 8: Installer and GitHub releases

**Files:** Create `Install/GitHubRelease.swift`, `Install/Installer.swift`, `InstallerTests.swift`, fixtures `release-multi-abi.json`, `release-no-apk.json`.

**Interfaces:**
- Produces: `struct ReleaseAsset { name: String; size: Int; url: URL }`, `struct Release { tag: String; prerelease: Bool; assets: [ReleaseAsset] }`.
- Produces: `enum GitHubRelease { static func parseRepo(_ input: String) -> (owner: String, repo: String)?; static func latest(owner: String, repo: String, session: URLSession) async throws -> Release; static func pick(_ assets: [ReleaseAsset], abis: [String]) -> AssetChoice }`, `enum AssetChoice { case one(ReleaseAsset), ambiguous([ReleaseAsset]), none }`.
- Produces: `actor Installer { init(adb: ADBRunner); func install(apk: URL, on: DeviceProfile) async throws; func installLatest(of: String, on: DeviceProfile, chooser: ([ReleaseAsset]) async -> ReleaseAsset?) async throws }`. HTTPS only; verify downloaded size equals `size`; `.apk` only (no `.apks`/`.xapk` in slice A).

- [ ] **Step 1:** Tests: `parsesRepoURLs` (`https://github.com/o/r`, `o/r`, trailing `.git`/slash, garbage nil), `picksMatchingABI`, `prefersUniversalWhenNoABIMatch`, `ambiguousWhenSeveralFit`, `noneWithoutAPK`, `rateLimitedThrowsFriendly` (HTTP 403 + `x-ratelimit-remaining: 0`), `rejectsTruncatedDownload`, `installUsesSerial`.
- [ ] **Step 2–4:** FAIL → implement (`URLProtocol` stub in tests) → PASS. Commit `feat: local and GitHub installer`.

### Task 9: Console guard

**Files:** Create `Console/ConsoleGuard.swift`, `ConsoleGuardTests.swift`.

**Interfaces:**
- Produces: `enum ConsoleVerdict: Equatable { case allow, confirm(reason: String) }`; `enum ConsoleGuard { static func classify(_ command: String) -> ConsoleVerdict }` — splits on `; && || |` newlines, `$( )` and backticks, then checks every segment's verb (`rm`, `reboot`, `recovery`, `wipe`, `dd`, `mkfs`, `format`, `su`, `pm clear`, `pm uninstall`, `pm disable*`, `settings put|delete`, `wm`, `setprop`, `cmd package`…).
- Produces: `Console.run(_:on:adb:log:) async throws -> String` — raw `adb shell`, logs command and exit code, never auto-confirms.

- [ ] **Step 1:** Tests (table): `ls /sdcard` allow; `rm -rf /sdcard/x` confirm; `ls; rm x` confirm; `echo $(reboot)` confirm; `` echo `pm clear a.b` `` confirm; `ls && settings put global x 1` confirm; `echo "rm"` allow-or-confirm documented (quoted text may over-confirm; over-confirming is acceptable, under-confirming is not).
- [ ] **Step 2–4:** FAIL → implement → PASS. Commit `feat: guarded raw console`.

### Task 10: App shell, theme, devices, pairing

**Files:** Create `Sources/Tether/{App,Theme,AppModel}.swift`, `Views/{RootView,Sidebar,DeviceRow,PairingSheet,Overview}.swift`.

**Interfaces:**
- Consumes: `DeviceManager`, `Discovery`, `ChangeEngine`, `RestorePointStore`, `CatalogStore`.
- Produces: `@MainActor @Observable final class AppModel { devices: [DeviceProfile]; selected: DeviceProfile?; section: Section; adb: ADBRunner /* honours TETHER_ADB env override, else bundled */; func refresh() async; func connect(host:port:) async }`; `enum Theme { static let quick: Animation = .snappy(duration: 0.2); static func tierColor(_: RiskTier) -> Color; static func tierSymbol(_: RiskTier) -> String }`; `PressScaleStyle: ButtonStyle` (0.97, no scale under Reduce Motion).
- Sections: Overview, Debloat, Tweaks, Apps, Backups, Console. Sidebar and toolbar use `glassEffect`; pairing sheet shows device-specific steps (Fire TV: *Settings → My Fire TV → Developer Options*; Android: Wireless debugging), discovery results, manual IP entry, and an actionable error on unauthorised/offline.

- [ ] **Step 1:** `swift build`; run with `TETHER_ADB=Tests/TetherCoreTests/Fixtures/fake-adb FAKE_ADB_DIR=<demo-state>` (committed demo state dir under `Tests/.../Fixtures/demo-state`).
- [ ] **Step 2:** Verify by running: sidebar lists the fake device, Add device sheet connects, Overview shows model/OS/vendor, VoiceOver labels present (check with Accessibility Inspector), Reduce Motion removes press scale. Commit `feat: app shell, sidebar, pairing`.

### Task 11: Debloat screen, inspector, action bar

**Files:** Create `Views/{DebloatView,InspectorView,ActionBar,TierBadge}.swift`.

**Interfaces:**
- Consumes: `Catalog.entries(for:installed:)`, `ChangeEngine.apply`, `RestorePointStore`.
- Behaviour: list grouped by vendor then tier, search, Safe preselected, Expert hidden behind a toggle. Selection raises a floating glass bar "Remove N · restore point will be saved" → confirm sheet (diff of packages) → progress → result sheet with applied/failed/pending and a Revert button. Inspector shows description, breaks note, revert history for the package.

- [ ] **Step 1:** Run against demo state: remove 3 Safe packages, confirm calls.log shows restore point first, then `pm uninstall -k --user 0`; Revert returns the demo state to its original (diff state files).
- [ ] **Step 2:** Commit `feat: debloat screen with restore-point flow`.

### Task 12: Tweaks, Apps, Backups, Console screens

**Files:** Create `Views/{TweaksView,AppsView,BackupsView,ConsoleView}.swift`.

- Tweaks: card per `Tweak`, segmented options, current value highlighted, apply through `ChangeEngine`.
- Apps: drop a `.apk` or paste a GitHub repo URL → asset chooser when ambiguous → install with progress; list installed user apps.
- Backups: restore points per device (date, reason, counts), Revert, reveal in Finder, delete.
- Console: input, output pane, guard confirm sheet for `.confirm`, history persisted in `ChangeLog`.

- [ ] **Step 1:** Run against demo state: apply "animations off", revert from Backups, install a fixture APK, run `getprop ro.product.model`, run `rm x` and see the confirm sheet. Commit `feat: tweaks, apps, backups, console screens`.

### Task 13: Docs, screenshots, private GitHub repo

**Files:** Create `README.md`, `docs/{architecture,safety-model,device-checklist}.md`, `docs/setup/{fire-tv,android}.md`, `scripts/screenshots.sh`, `docs/images/*.png`.

- [ ] **Step 1:** `screenshots.sh` launches the built `.app` with the fake-adb demo state, captures each section with `screencapture -l <windowid>` (window id via `osascript`); doubles as the launch smoke test (fails if no window within 10 s).
- [ ] **Step 2:** Write docs: README (what/why, screenshots, install + Gatekeeper first-run step, safety model summary, roadmap with Tizen slice B); `device-checklist.md` lists per-vendor manual checks including Fire TV tweak keys and Bonjour discovery.
- [ ] **Step 3:** Identity scrub: `git log --format='%an %ae' | sort -u` shows only `Ol775` + noreply; `grep -rIiE '<surname>|gmail' . --exclude-dir=.git --exclude-dir=.build` returns nothing (run with the real strings, not committed).
- [ ] **Step 4:** `swift test` all green, `./scripts/bundle.sh`, then `gh repo create Ol775/tether --private --source . --push`; confirm `gh repo view Ol775/tether --json visibility` is `PRIVATE`. Commit `docs: readme, guides, screenshots`.
