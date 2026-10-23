import Foundation
import Testing
@testable import TetherCore

struct TizenChangeEngineTests {
    let tv = TizenDevice(serial: "192.168.1.60:26101", deviceID: "DUID1", model: "QE55Q80AAT", modelYear: 2021, tizenVersion: "6.0", shellEnabled: false, rootAvailable: false)
    let a = TizenAppID("org.example.alpha")!, b = TizenAppID("org.example.bravo")!, c = TizenAppID("org.example.charlie")!

    struct Rig {
        let fake: FakeSDB, engine: TizenChangeEngine, store: TizenRestorePointStore, root: URL
        func apps() -> [String] { fake.lines("apps_list.txt") }
        func has(_ id: TizenAppID) -> Bool { apps().contains { $0.contains("'\(id.value)'") } }
        func mutatingCalls() -> [String] { fake.calls().filter { $0.contains("vd_appuninstall") || $0.contains("vd_appinstall") || $0.contains("push") } }
    }

    func rig(_ extra: [String: String] = [:], cli: URL? = nil, rootOverride: URL? = nil) throws -> Rig {
        let fake = try FakeSDB(files: [
            "apps_list.txt": "'Alpha'  'org.example.alpha'\n'Bravo'  'org.example.bravo'\n'Charlie'  'org.example.charlie'\n",
            "capability.txt": fixture("sdb-capability-2021.txt"),
        ].merging(extra) { $1 })
        let root = rootOverride ?? FileManager.default.temporaryDirectory.appendingPathComponent("tizeneng-\(UUID().uuidString)")
        let store = TizenRestorePointStore(root: root.appendingPathComponent("rp"))
        let engine = TizenChangeEngine(sdb: fake.runner, store: store, log: ChangeLog(file: root.appendingPathComponent("changes.jsonl")), tizenCLI: cli)
        return Rig(fake: fake, engine: engine, store: store, root: root)
    }

    /// A real signed-shaped `.wgt`: a zip whose `config.xml` declares a `tizen:application` id equal to
    /// the file's base name, so the engine reads the same id the fake sdb registers.
    func wgt(_ name: String) throws -> URL {
        let id = (name as NSString).deletingPathExtension
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("wgtsrc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let config = """
        <?xml version="1.0" encoding="UTF-8"?>
        <widget xmlns:tizen="http://tizen.org/ns/widgets" id="http://tether.test/\(id)">
            <tizen:application id="\(id)" package="\(id)" required_version="2.3"/>
            <content src="index.html"/>
        </widget>
        """
        try config.write(to: src.appendingPathComponent("config.xml"), atomically: true, encoding: .utf8)
        try "<html></html>".write(to: src.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wgt-\(UUID().uuidString)").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-j", "-q", url.path, src.appendingPathComponent("config.xml").path, src.appendingPathComponent("index.html").path]
        try zip.run(); zip.waitUntilExit()
        return url
    }

    @Test func uninstallThenVerify() async throws {
        let r = try rig()
        let report = try await r.engine.apply([.uninstall(a)], on: tv, reason: "t")
        #expect(report.applied == [.uninstall(a)] && report.failed == nil && report.locked.isEmpty && report.verified)
        #expect(!r.has(a) && r.has(b))
    }

    @Test func lockedAppIsReportedNotApplied() async throws {
        let r = try rig(["locked_apps.txt": "org.example.bravo\n"])
        let report = try await r.engine.apply([.uninstall(b), .uninstall(a)], on: tv, reason: "t")
        #expect(report.locked == [b] && report.applied == [.uninstall(a)] && report.failed == nil)
        #expect(r.has(b) && !r.has(a))
    }

    @Test func noCommandRunsWhenTheRestorePointCannotBeWritten() async throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("blocker-\(UUID().uuidString)")
        try Data().write(to: blocker)
        let r = try rig(rootOverride: blocker)   // a file where the folder should be
        await #expect(throws: (any Error).self) { try await r.engine.apply([.uninstall(a)], on: tv, reason: "t") }
        #expect(r.mutatingCalls().isEmpty && r.has(a))
    }

    @Test func offlineMidRunKeepsTheReport() async throws {
        let r = try rig(["fail_after": "1"])
        let report = try await r.engine.apply([.uninstall(a), .uninstall(b), .uninstall(c)], on: tv, reason: "t")
        #expect(report.applied == [.uninstall(a)] && report.failed?.0 == .uninstall(b) && report.pending == [.uninstall(c)])
        #expect(report.failed?.1 == .notConnected)
    }

    @Test func revertReinstallsAppsTetherInstalled() async throws {
        let r = try rig()
        let engine = signedEngine(r, cli: try permitCLI(r))
        _ = try await engine.apply([.install(wgt: try wgt("zulu.wgt"))], on: tv, reason: "install")
        #expect(r.has(TizenAppID("zulu")!))
        let removal = try await engine.apply([.uninstall(TizenAppID("zulu")!)], on: tv, reason: "remove")
        #expect(!r.has(TizenAppID("zulu")!))
        let reverted = try await engine.revert(removal.restorePoint, on: tv)
        #expect(reverted.failed == nil && reverted.cannotRestore.isEmpty && r.has(TizenAppID("zulu")!))
    }

    @Test func revertSaysItCannotRestorePreloads() async throws {
        let r = try rig()
        let removal = try await r.engine.apply([.uninstall(a)], on: tv, reason: "remove")
        let before = r.mutatingCalls().count
        let reverted = try await r.engine.revert(removal.restorePoint, on: tv)
        #expect(reverted.cannotRestore == [a] && reverted.applied.isEmpty && r.mutatingCalls().count == before)
    }

    @Test func secondRunIsRefusedWhileOneRuns() async throws {
        let r = try rig(["sleep": "0.2"])
        async let first = r.engine.apply([.uninstall(a)], on: tv, reason: "first")
        try await Task.sleep(for: .milliseconds(100))
        await #expect(throws: TizenError.busy) { try await r.engine.apply([.uninstall(b)], on: tv, reason: "second") }
        _ = try await first
    }

    @Test func revertRefusesAnotherTV() async throws {
        let r = try rig()
        let removal = try await r.engine.apply([.uninstall(a)], on: tv, reason: "remove")
        let other = TizenDevice(serial: "192.168.1.61:26101", deviceID: "DUID2", model: "QE55Q80AAT", modelYear: 2021, tizenVersion: "6.0", shellEnabled: false, rootAvailable: false)
        await #expect(throws: TizenError.wrongDevice) { try await r.engine.revert(removal.restorePoint, on: other) }
    }

    @Test func invalidInstallFilesAreRefusedBeforeAnyCall() async throws {
        let r = try rig()
        let missing = URL(fileURLWithPath: "/nonexistent/app.wgt")
        let wrongType = try wgt("app.exe")
        for bad in [missing, wrongType] {
            await #expect(throws: TizenError.unsafeValue) { try await r.engine.apply([.install(wgt: bad)], on: tv, reason: "t") }
        }
        #expect(r.fake.calls().isEmpty)
    }

    @Test func fallsBackToTheTizenCLIWhenVdUninstallIsUnavailable() async throws {
        let cli = FileManager.default.temporaryDirectory.appendingPathComponent("faketizen-\(UUID().uuidString)")
        let r0 = try rig(["no_vd": ""])
        let script = "#!/bin/bash\necho \"$*\" >> '\(r0.fake.dir.path)/tizen.log'\ngrep -vF -- \"'$3'\" '\(r0.fake.dir.path)/apps_list.txt' > '\(r0.fake.dir.path)/t.tmp'; mv '\(r0.fake.dir.path)/t.tmp' '\(r0.fake.dir.path)/apps_list.txt'\n"
        try script.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let engine = TizenChangeEngine(sdb: r0.fake.runner, store: r0.store, log: ChangeLog(file: r0.root.appendingPathComponent("c.jsonl")), tizenCLI: cli)
        let report = try await engine.apply([.uninstall(a)], on: tv, reason: "t")
        #expect(report.applied == [.uninstall(a)] && !r0.has(a))
        #expect(r0.fake.lines("tizen.log").first == "uninstall -p org.example.alpha -s 192.168.1.60:26101")
    }

    @Test func anEmptyAppListBeforeARemovalIsAFailedReadNotSuccess() async throws {
        let r = try rig(["apps_list.txt": ""])
        await #expect(throws: (any Error).self) { try await r.engine.apply([.uninstall(a)], on: tv, reason: "t") }
        #expect(r.mutatingCalls().isEmpty)
    }

    @Test func anEmptyReReadAfterARemovalIsNotConfirmation() async throws {
        let r = try rig(["blank_after_uninstall": ""])
        let report = try await r.engine.apply([.uninstall(a), .uninstall(b)], on: tv, reason: "t")
        #expect(report.applied.isEmpty && report.failed?.0 == .uninstall(a) && report.pending == [.uninstall(b)] && !report.verified)
    }

    @Test func anAppAlreadyMissingIsSkippedNotCountedAsApplied() async throws {
        let r = try rig()
        let ghost = TizenAppID("org.example.zzz")!
        let report = try await r.engine.apply([.uninstall(ghost)], on: tv, reason: "t")
        #expect(report.skipped == [.uninstall(ghost)] && report.applied.isEmpty)
        #expect(r.mutatingCalls().isEmpty)
    }

    @Test func fallsBackWhenVdUninstallPrintsNotFoundWithExitZero() async throws {
        let cli = FileManager.default.temporaryDirectory.appendingPathComponent("faketizen-\(UUID().uuidString)")
        let r0 = try rig(["no_vd_exit0": ""])
        let script = "#!/bin/bash\ngrep -vF -- \"'$3'\" '\(r0.fake.dir.path)/apps_list.txt' > '\(r0.fake.dir.path)/t.tmp'; mv '\(r0.fake.dir.path)/t.tmp' '\(r0.fake.dir.path)/apps_list.txt'\n"
        try script.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let engine = TizenChangeEngine(sdb: r0.fake.runner, store: r0.store, log: ChangeLog(file: r0.root.appendingPathComponent("c.jsonl")), tizenCLI: cli)
        let report = try await engine.apply([.uninstall(a)], on: tv, reason: "t")
        #expect(report.applied == [.uninstall(a)] && report.locked.isEmpty && !r0.has(a))
    }

    // MARK: installSigned

    /// Fake `tizen` CLI: logs its arguments and only serves `install-permit` now that the engine installs
    /// through sdb (`push` + `vd_appinstall`), not the CLI. `failing` makes the permit step fail.
    func permitCLI(_ r: Rig, failing: Bool = false) throws -> URL {
        let cli = FileManager.default.temporaryDirectory.appendingPathComponent("faketizen-\(UUID().uuidString)")
        let script = """
        #!/bin/bash
        D='\(r.fake.dir.path)'
        echo "$*" >> "$D/tizen.log"
        if [[ "$1" == install-permit ]]; then
        \(failing ? "echo 'permit denied' >&2; exit 1" : "exit 0")
        fi
        """
        try script.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        return cli
    }

    func signedEngine(_ r: Rig, cli: URL?) -> TizenChangeEngine {
        TizenChangeEngine(sdb: r.fake.runner, store: r.store, log: ChangeLog(file: r.root.appendingPathComponent("s.jsonl")), tizenCLI: cli)
    }

    @Test func installSignedSnapshotsThenPermitsThenInstallsOnTheExactSerial() async throws {
        let r = try rig()
        let jf = TizenAppID("jellyfin")!
        let report = try await signedEngine(r, cli: try permitCLI(r)).apply([.installSigned(wgt: try wgt("jellyfin.wgt"), expectedApp: jf)], on: tv, reason: "jf")
        #expect(report.applied.count == 1 && report.failed == nil && report.verified)
        #expect(r.fake.lines("tizen.log").first == "install-permit -s 192.168.1.60:26101")
        // Installed through sdb on the exact serial: push the package, then vd_appinstall by app id.
        let calls = r.fake.calls()
        #expect(calls.contains { $0.hasPrefix("-s 192.168.1.60:26101 push ") && $0.hasSuffix("tether-install.wgt") })
        #expect(calls.contains { $0 == "-s 192.168.1.60:26101 shell 0 vd_appinstall jellyfin /home/owner/share/tmp/sdk_tools/tmp/tether-install.wgt" })
        let points = await r.store.list(), cached = await r.store.wgt(for: jf)
        #expect(points.count == 1 && cached != nil)
        #expect(!r.fake.calls().contains { $0.contains("uninstall") })
    }

    @Test func aFailedPermitPreventsTheInstallButKeepsTheRestorePoint() async throws {
        let r = try rig()
        let jf = TizenAppID("jellyfin")!
        let report = try await signedEngine(r, cli: try permitCLI(r, failing: true)).apply([.installSigned(wgt: try wgt("jellyfin.wgt"), expectedApp: jf)], on: tv, reason: "jf")
        #expect(report.applied.isEmpty && report.failed != nil && !r.has(jf))
        let points = await r.store.list()
        #expect(points.count == 1)
    }

    @Test func installSignedWithoutTheTizenCLIFailsBeforeAnySDBInstall() async throws {
        let r = try rig()
        let report = try await signedEngine(r, cli: nil).apply([.installSigned(wgt: try wgt("jellyfin.wgt"), expectedApp: TizenAppID("jellyfin")!)], on: tv, reason: "jf")
        #expect(report.failed?.1 == .toolsMissing && !r.has(TizenAppID("jellyfin")!))
    }

    @Test func aWrongExpectedIDIsAFailureAndNothingIsCached() async throws {
        let r = try rig()
        let other = TizenAppID("somethingelse")!
        let report = try await signedEngine(r, cli: try permitCLI(r)).apply([.installSigned(wgt: try wgt("jellyfin.wgt"), expectedApp: other)], on: tv, reason: "jf")
        let cached = await r.store.wgt(for: other)
        #expect(report.applied.isEmpty && report.failed != nil && cached == nil)
    }

    @Test func anExitZeroInstallFailureIsReported() async throws {
        let r = try rig(["force_install_failure": ""])
        let jf = TizenAppID("jellyfin")!
        let report = try await signedEngine(r, cli: try permitCLI(r)).apply([.installSigned(wgt: try wgt("jellyfin.wgt"), expectedApp: jf)], on: tv, reason: "jf")
        let cached = await r.store.wgt(for: jf)
        #expect(report.applied.isEmpty && report.failed != nil && cached == nil)
    }

    @Test func anUpdateOfAnAlreadyInstalledAppStillCachesThePackage() async throws {
        let jf = TizenAppID("jellyfin")!
        let r = try rig(["apps_list.txt": "'Alpha'  'org.example.alpha'\n'Jellyfin'  'jellyfin'\n"])
        let report = try await signedEngine(r, cli: try permitCLI(r)).apply([.installSigned(wgt: try wgt("jellyfin.wgt"), expectedApp: jf)], on: tv, reason: "jf")
        let cached = await r.store.wgt(for: jf)
        #expect(report.applied.count == 1 && report.verified && cached != nil)
        #expect(!r.fake.calls().contains { $0.contains("uninstall") })
    }

    /// Shapes quoted in public Samsung/Tizen forum posts; the exact text on a real TV is still unconfirmed.
    @Test func installOutputShapesFromPublicReports() throws {
        try TizenChangeEngine.checkInstallOutput("__return_cb req_id[1] pkg_type[wgt] pkgid[fUhAZM7hJJ] key[end] val[ok]\nspend time for pkgcmd is [4667]ms")
        try TizenChangeEngine.checkInstallOutput("app_id[Jellyfin] install completed")
        for bad in ["key[error] val[22]\nprocessing result : SIGNATURE_INVALID [22] failed\nkey[end] val[fail]",
                    "app_id[MyApp] install failed[118019]", "installing[10]", ""] {
            #expect(throws: (any Error).self) { try TizenChangeEngine.checkInstallOutput(bad) }
        }
    }
}
