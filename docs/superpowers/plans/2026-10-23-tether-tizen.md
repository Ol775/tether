# Tether Tizen (slice B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Manage Samsung Tizen TVs (2019+) over network `sdb`: connect, list apps, install signed `.wgt`, remove what the TV allows, restore point and revert, with Samsung's tools fetched on first use.

**Architecture:** A parallel Tizen pipeline in `TetherCore` (`SDBRunner`, `TizenDevice`, `TizenChangeEngine`, `TizenRestorePointStore`) sharing the extracted process runner, `RiskTier`, `ChangeLog` and the UI patterns of slice A. Android's `Change`/`ChangeEngine` are adb-shaped and are not generalised: only the second implementation exists, so extraction is limited to the process runner.

**Tech Stack:** Swift 6.4, SwiftPM (tools 6.2), SwiftUI/Liquid Glass, Swift Testing, scripted fake `sdb`.

**Spec:** `docs/superpowers/specs/2026-10-23-tether-tizen-design.md` (approved by the owner 2026-10-23). Slice A spec and code are the pattern.

## Global Constraints

- macOS 26+, Swift 6.4; public identity only handle `Ol775` + `41142034+Ol775@users.noreply.github.com`; no real name, surname or gmail in code, history, fixtures or screenshots; homelab IPs never committed.
- Never use Codex agents on this project.
- Samsung binaries are never committed or redistributed; they are downloaded by the user's app on explicit licence acceptance.
- Every value reaching `sdb`/`tizen` is validated first (`TizenAppID`: ASCII letters, digits, `.`, `_`, `-`, 1–128 chars; host/port as `DeviceManager.endpoint`). No shell string building; arguments are an array.
- A restore point is written and verified before any mutating command; ordering and failure reporting match slice A (`ChangeReport` semantics: applied / failed / pending / verified).
- Models before 2019 are refused with a plain explanation. Locked apps are shown as locked, never as a button that fails.
- Rooting and any exploit path are out of scope.
- No Tizen debloat entry may claim "verified"; `source` must say how the claim was obtained.

## Review Focus

1. TV answers `sdb connect` with "failed to connect" or an empty device list while exiting 0: must become a typed error with the Developer Mode / host-IP next step, not "connected".
2. Uninstall that exits 0 but the app is still present (Samsung lock): must be reported as `lockedBySamsung`, remembered for that TV, and never counted as applied.
3. TV drops mid-removal: report survives (as in slice A), revert refuses to guess and says what it can and cannot restore.
4. Two TVs, or the same TV at a new IP: restore points keyed by a stable ID (`duid` from `sdb capability`, else model+serial), address-change confirm as in slice A.
5. Tools not installed / installer download corrupted or interrupted: nothing half-installed is used; the next launch retries cleanly and the licence is shown again only if not yet accepted.

---

### Task 1: Shared process runner, SDBRunner, SDBError, fake sdb

**Files:** Create `Sources/TetherCore/ADB/ProcessRunner.swift`, `Sources/TetherCore/Tizen/SDBRunner.swift`, `Sources/TetherCore/Tizen/SDBError.swift`, `Tests/TetherCoreTests/Fixtures/fake-sdb`, `Tests/TetherCoreTests/SDBRunnerTests.swift`, `Tests/TetherCoreTests/FakeSDB.swift`. Modify `ADBRunner.swift` to call the shared runner.

**Interfaces:**
- Produces: `enum ProcessRunner { static func run(_ exe: URL, _ args: [String], timeout: Duration) async throws -> (status: Int32, out: String, err: String) }` (the existing temp-file/timeout/cancel logic, moved unchanged; throws `ProcessRunnerError.launchFailed`, `.timeout`).
- Produces: `actor SDBRunner { init(executable: URL, defaultTimeout: Duration = .seconds(15)); func run(_ args: [String], serial: String? = nil, timeout: Duration? = nil) async throws -> String }` (prefix `-s <serial>`).
- Produces: `enum SDBError: Error, Equatable, Sendable { case toolsMissing, timeout, developerModeOff, refused, notConnected, commandFailed(code: Int32, output: String) }` with `advice: String` and `static func classify(code:output:)`.
- Produces: `fake-sdb` (bash, state in `$FAKE_SDB_DIR` beside the script): `connect`, `disconnect`, `devices`, `capability`, `shell 0 applist`, `shell 0 vd_appuninstall <id>`, `install`; every call appended to `calls.log`; `sleep`, `force_error`, `fail_after` files as in `fake-adb`; `locked_apps.txt` makes uninstall exit 0 without removing.

- [ ] **Step 1:** Write `SDBRunnerTests`: `passesSerial` (log line starts `-s 192.168.1.60:26101 `), `timesOut`, `missingBinaryIsToolsMissing`, `classifiesRefusedAndDeveloperMode` (`failed to connect to remote target` → `.refused`; `closed` → `.notConnected`), and keep all existing `ADBRunnerTests` green.
- [ ] **Step 2:** `swift test --filter SDBRunnerTests` → FAIL (types missing).
- [ ] **Step 3:** Move the exec body of `ADBRunner` into `ProcessRunner`; `ADBRunner` keeps its API and error mapping. Implement `SDBRunner`/`SDBError`, `fake-sdb`, `FakeSDB` helper (mirrors `FakeADB`).
- [ ] **Step 4:** `swift test` → whole suite passes (72+ prior tests unchanged). Commit `feat: shared process runner, SDBRunner, fake sdb`.

### Task 2: Tizen device profile and parsers

**Files:** Create `Sources/TetherCore/Tizen/TizenDevice.swift`, `Sources/TetherCore/Tizen/TizenParsers.swift`, `Tests/TetherCoreTests/TizenParsersTests.swift`, fixtures `sdb-capability-2021.txt`, `sdb-capability-2019.txt`, `sdb-devices.txt`, `sdb-applist.txt` (assumed formats, labelled as such in a header comment).

**Interfaces:**
- Produces: `struct TizenDevice: Codable, Equatable, Sendable, Identifiable { serial, deviceID, model, modelYear: Int?, tizenVersion: String, shellEnabled: Bool, rootAvailable: Bool; var id }`.
- Produces: `enum TizenParsers { static func devices(_:) -> [(serial: String, state: String)]; static func capability(_:) -> [String: String]; static func device(serial:capability:) -> TizenDevice; static func apps(_:) -> [TizenApp]; static func modelYear(fromModelCode:) -> Int? }`, `struct TizenApp: Codable, Hashable, Sendable { id: TizenAppID, name: String, version: String? }`, `struct TizenAppID` (validated, Codable as string).
- Year letters from the model code: R=2019, T=2020, A=2021, B=2022, C=2023, D=2024, F=2025 (e.g. `QN65Q80TAFXZA` → 2020, `UE55AU8000` handled by returning nil when no letter matches).

- [ ] **Step 1:** Tests: `yearFromModelCode` table (`QN65Q80TAFXZA`→2020, `UE50RU7100`→2019, `QE55Q80BAT`→2022, `UN55NU8000`→2018, `garbage`→nil), `deviceIDPrefersDUIDOverSerial`, `placeholderIDsFallBack`, `hostileAppIDsAreRejected` (`a;rm`, `../x`, empty, 129 chars), `appListParsesAndDropsHostileLines`.
- [ ] **Step 2:** `swift test --filter TizenParsersTests` → FAIL.
- [ ] **Step 3:** Implement. `deviceID` ignores empty/placeholder values like slice A's `isRealSerial`.
- [ ] **Step 4:** PASS, full suite green. Commit `feat: Tizen device profile and parsers`.

### Task 3: TizenManager (connect, devices, refusal handling)

**Files:** Create `Sources/TetherCore/Tizen/TizenManager.swift`, `Tests/TetherCoreTests/TizenManagerTests.swift`. Modify `DeviceManager.swift` to expose `static func endpoint` as `internal`.

**Interfaces:**
- Consumes: `SDBRunner`, `DeviceManager.endpoint`.
- Produces: `actor TizenManager { init(sdb: SDBRunner); func connect(host: String, port: Int = 26101) async throws; func disconnect(serial: String) async throws; func devices() async throws -> [TizenDevice] }`; refuses `modelYear < 2019` with `TizenError.unsupportedModel(year: Int)`; `enum TizenError: Error, Equatable, Sendable { case unsupportedModel(year: Int), unsafeValue, lockedBySamsung(TizenAppID), nothingToDo, wrongDevice, busy }` with `advice`.

- [ ] **Step 1:** Tests: `connectSucceeds`, `connectFailureTextBecomesRefusedEvenWithExitZero` (Review Focus 1), `offlineDevicesAreSkipped`, `hostileHostRejectedBeforeAnyCall`, `preTwentyNineteenTVIsRefused`.
- [ ] **Step 2:** FAIL. **Step 3:** Implement (`connect` inspects text for `connected to` / `already connected`; anything else → `SDBError.classify`). **Step 4:** PASS, suite green. Commit `feat: TizenManager`.

### Task 4: Restore points and change engine (uninstall, install, revert)

**Files:** Create `Sources/TetherCore/Tizen/TizenChange.swift`, `TizenRestorePoint.swift`, `TizenRestorePointStore.swift`, `TizenChangeEngine.swift`, `Tests/TetherCoreTests/TizenChangeEngineTests.swift`.

**Interfaces:**
- Produces: `enum TizenChange: Codable, Hashable, Sendable { case uninstall(TizenAppID), install(wgt: URL) }` (`install` path validated: existing file ending `.wgt`/`.tpk`).
- Produces: `struct TizenRestorePoint: Codable, Identifiable, Equatable, Sendable { id, createdAt, reason, device: TizenDevice, apps: [TizenApp], wgts: [String: String] /* appID → relative path of the signed package Tether installed */, changes: [TizenChange] }`.
- Produces: `actor TizenRestorePointStore { init(root: URL); create(device:reason:apps:changes:) -> TizenRestorePoint` (JSON read-back verified, folder removed on failure); `list/load/delete`; `saveWGT(_:for:in:)`.
- Produces: `struct TizenReport: Sendable { restorePoint, applied, failed: (TizenChange, SDBError)?, pending, locked: [TizenAppID], verified: Bool }`.
- Produces: `actor TizenChangeEngine { init(sdb: SDBRunner, store: TizenRestorePointStore, log: ChangeLog, tizenCLI: URL?); apply(_ changes:on:reason:) -> TizenReport; revert(_:on:) -> TizenReport }`.
- Uninstall strategy order: `sdb shell 0 vd_appuninstall <id>`; if the device lacks it, `tizen uninstall -p <id> -t <serial>`. After each, re-read `applist`; still present → `locked`, stop counting it as applied, remember in `locked`. Revert reinstalls only apps whose signed package is in the restore point; others are reported "ask Smart Hub".
- One run per device at a time (`ChangeError.busy`-style guard); revert checks `deviceID`, vendor model equality.

- [ ] **Step 1:** Tests against `fake-sdb`: `uninstallThenVerify`, `lockedAppIsReportedNotApplied` (exit 0, still listed → in `locked`, `applied` empty), `restorePointWrittenBeforeFirstCommand` (calls log order), `offlineMidRunKeepsReport` (Review Focus 3, `fail_after`), `revertReinstallsTetherInstalledApps`, `revertSaysItCannotRestorePreloads`, `secondRunIsRefusedWhileOneRuns`, `revertRefusesOtherTV`, `hostileIDBlockedBeforeSnapshot`.
- [ ] **Step 2:** FAIL. **Step 3:** Implement mirroring `ChangeEngine`. **Step 4:** PASS, suite green. Commit `feat: Tizen restore points and change engine`.

### Task 5: Tizen catalog

**Files:** Create `Sources/TetherCore/Tizen/TizenCatalog.swift`, `Sources/TetherCore/Resources/tizen-catalog.json`, `Tests/TetherCoreTests/TizenCatalogTests.swift`, `docs/catalog-format.md` section.

**Interfaces:**
- Produces: `struct TizenCatalogEntry: Codable, Identifiable, Sendable { app: TizenAppID, tier: RiskTier, title, description, breaks: String?, removableFromYear: Int?, source: String }`; `struct TizenCatalog { static func decode(_ data: Data) throws -> TizenCatalog; func entries(for device: TizenDevice, installed: Set<TizenAppID>) -> [TizenCatalogEntry]; func likelyLocked(_:on:) -> Bool }` (true when `removableFromYear` is nil or later than the TV's year; a hint only).
- Validation as slice A (non-empty fields, duplicates, `breaks` required for advanced+, version 1). Reuses the loader (`Resources.url`). Seed with a handful of unverified entries (`source` says "community reports, not verified on device").

- [ ] **Step 1:** Tests: `decodesBundledCatalog`, `rejectsDuplicatesAndMissingBreaks`, `hintMarksPreloadsAsLikelyLocked`, `filtersToInstalled`. **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** PASS. Commit `feat: Tizen catalog`.

### Task 6: Samsung tools setup

**Files:** Create `Sources/TetherCore/Tizen/SamsungTools.swift`, `Tests/TetherCoreTests/SamsungToolsTests.swift`.

**Interfaces:**
- Produces: `actor SamsungTools { init(home: URL, session: URLSession = .shared, installerURL: URL = SamsungTools.defaultInstallerURL); var sdb: URL?; var tizenCLI: URL?; var isInstalled: Bool; func install(acceptingLicense: Bool, progress: @Sendable (String) -> Void) async throws }`.
- `defaultInstallerURL`: Samsung's official CLI installer on `download.tizen.org` (https only; macOS 64-bit; runs under Rosetta on Apple silicon). Download to a temp file, record its sha256 in the change log, run it with `--accept-license <home>/tizen-studio`, install the certificate add-on through the bundled package manager, then check `sdb` and `tizen` exist. `acceptingLicense == false` throws before any download. Non-https URL refused. A failed or partial run deletes `<home>/tizen-studio` and a `.incomplete` marker blocks use (Review Focus 5).

- [ ] **Step 1:** Tests with a stub `URLProtocol` and a scripted fake installer script: `refusesWithoutLicense`, `refusesHTTP`, `successfulRunExposesToolPaths`, `failedInstallerLeavesNothingUsable`, `interruptedRunIsRetriedCleanly`. **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** PASS. Commit `feat: Samsung tools setup`.
- Note: running the real Samsung installer is a manual checklist item (large download, licence); not run in CI or by the implementer.

### Task 7: Certificates (guided)

**Files:** Create `Sources/TetherCore/Tizen/TizenCertificates.swift`, `Tests/TetherCoreTests/TizenCertificatesTests.swift`, `docs/setup/samsung-tv.md`.

**Interfaces:**
- Produces: `struct TizenCertificates { init(tools: SamsungTools); func state(for device: TizenDevice) async -> CertificateState }` with `enum CertificateState: Equatable, Sendable { case ready, missing, notForThisTV, toolsMissing }`; checks the active profile via the `tizen security-profiles` listing and whether the TV's DUID is present. It does not create certificates: it returns the next step text and the path of Certificate Manager to open (spike 1 is documented in `docs/setup/samsung-tv.md` as unresolved until run on hardware).

- [ ] **Step 1:** Tests with a fake `tizen` script: `readyWhenProfileListsDUID`, `notForThisTVWhenDUIDMissing`, `missingWhenNoProfile`, `toolsMissingWithoutTools`. **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** PASS. Commit `feat: guided Tizen certificate check`.

### Task 8: App wiring (model, sidebar, pairing, setup)

**Files:** Modify `Sources/Tether/AppModel.swift`, `Sidebar.swift`, `PairingSheet.swift`, `RootView.swift`; create `Sources/Tether/Views/TizenSetupSheet.swift`.

**Interfaces:**
- Consumes: Tasks 1–7.
- `AppModel` gains `tizenDevices: [TizenDevice]`, `selectedTizen: TizenDevice?`, `tizenApps: [TizenApp]`, `tizenRestorePoints`, `tizenLocked: Set<TizenAppID>` (persisted per `deviceID` in Application Support), `func connectTizen(host:port:)`, `applyTizen(_:reason:)`, `revertTizen(_:)` (same busy guard, report-before-reload ordering, address-change confirmation as slice A), `func setUpSamsungTools(acceptingLicense:)`. Selecting a TV clears Android snapshot and vice versa (no stale data).
- Sidebar lists Android and Tizen devices together, TV rows labelled with year; Tizen sections: Overview, Debloat, Apps, Backups. Pairing sheet gets a "Samsung TV" mode: Developer Mode steps (Apps → 12345 → Developer mode ON → enter this Mac's IP → restart TV), shows the Mac's current LAN IP to copy, port 26101, Connect. Setup sheet shows the licence text link and an explicit "I accept" before downloading.

- [ ] **Step 1:** Add the model plumbing; `swift build` clean. **Step 2:** Run the existing suite (green). **Step 3:** Commit `feat: wire Tizen devices into the app model and sidebar`. (UI wiring has no unit tests; verified by the demo run in Task 10.)

### Task 9: Tizen views

**Files:** Create `Sources/Tether/Views/TizenOverviewView.swift`, `TizenDebloatView.swift`, `TizenAppsView.swift`, `TizenBackupsView.swift`; modify `DetailRouter`.

**Interfaces:** Debloat lists installed apps with catalog tier badges; entries flagged likely-locked or in `tizenLocked` show "Locked by Samsung" with the reason and no remove control; floating glass action bar and confirm sheet as slice A (expert tier needs "I understand"); report sheet lists applied / locked / pending. Apps: install a signed `.wgt`/`.tpk` from a file picker, shows certificate state and next step when not ready, list and uninstall apps Tether installed. Backups: list/delete/revert with the address-change confirm. Reduce Motion honoured on every explicit animation in the new views.

- [ ] **Step 1:** Implement views; `swift build` clean. **Step 2:** `swift test` green. **Step 3:** Commit `feat: Tizen debloat, apps, backups views`.

### Task 10: Demo, screenshots, docs, bundle

**Files:** Create `demo/state-tizen/*`, extend `demo/run.sh` (`TETHER_TIZEN_DEMO=1` uses `fake-sdb` copy and a demo TV at `192.168.1.60:26101`, model `QN65Q80TAFXZA`), `docs/setup/samsung-tv.md` (final), `docs/tizen-device-checklist.md`, update `README.md`, `docs/architecture.md`, `docs/safety-model.md`, `docs/images/tizen-debloat.png`, `tizen-apps.png`; modify `scripts/screenshots.sh`, `scripts/bundle.sh` (no Samsung binaries bundled).

- [ ] **Step 1:** Run the demo with fake sdb, capture screenshots, view each. **Step 2:** `./scripts/bundle.sh` succeeds and the bundle contains no Samsung binaries. **Step 3:** Identity scrub greps clean (tree and history). **Step 4:** `swift test` green. Commit `docs: Tizen guides, checklist, screenshots`.

### Final review (executing-plans)

One whole-branch review on the most capable model with the Review Focus above, then one fix pass, then `gh`-less push (`git push` to the existing private repo).
