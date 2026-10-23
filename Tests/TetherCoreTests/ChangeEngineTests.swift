import Foundation
import Testing
@testable import TetherCore

struct ChangeEngineTests {
    let device = DeviceProfile(serial: "192.168.1.5:5555", vendor: "amazon", model: "AFTMM", androidVersion: "9", sdk: 28, abis: ["armeabi-v7a"], platform: .fireOS)
    let a = PackageName("com.amazon.alpha")!, b = PackageName("com.amazon.bravo")!
    let c = PackageName("com.amazon.charlie")!, d = PackageName("com.amazon.delta")!

    struct Rig {
        let fake: FakeADB, engine: ChangeEngine, root: URL, log: URL
        func installed() -> Set<String> { Set(fake.lines("packages_installed.txt")) }
        func globalSettings() -> [String: String] { Parsers.settings(fake.lines("settings_global.txt").joined(separator: "\n")) }
        func mutatingCalls() -> [String] { fake.calls().filter { $0.contains("uninstall") || $0.contains("settings put") || $0.contains("settings delete") || $0.contains(" install") || $0.contains("wm density ") } }
    }

    func rig(_ extra: [String: String] = [:]) throws -> Rig {
        let fake = try FakeADB(files: [
            "packages_all.txt": "com.amazon.alpha\ncom.amazon.bravo\ncom.amazon.charlie\ncom.amazon.delta\n",
            "packages_installed.txt": "com.amazon.alpha\ncom.amazon.bravo\ncom.amazon.charlie\ncom.amazon.delta\n",
            "settings_global.txt": "window_animation_scale=1.0\nadb_enabled=1\n",
        ].merging(extra) { $1 })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("eng-\(UUID().uuidString)")
        let log = root.appendingPathComponent("changes.jsonl")
        let engine = ChangeEngine(adb: fake.runner, store: RestorePointStore(root: root.appendingPathComponent("rp"), adb: fake.runner), log: ChangeLog(file: log))
        return Rig(fake: fake, engine: engine, root: root, log: log)
    }

    @Test func removesThenRevertsToIdenticalState() async throws {
        let r = try rig()
        let report = try await r.engine.apply([.removePackage(a), .setSetting(ns: .global, key: "window_animation_scale", value: "0")], on: device, reason: "t")
        #expect(report.applied.count == 2 && report.failed == nil && report.pending.isEmpty && report.verified)
        #expect(!r.installed().contains(a.value))
        #expect(r.globalSettings()["window_animation_scale"] == "0")

        let reverted = try await r.engine.revert(report.restorePoint, on: device)
        #expect(reverted.failed == nil && reverted.verified)
        #expect(r.installed().contains(a.value))
        #expect(r.globalSettings()["window_animation_scale"] == "1.0")
        #expect(r.globalSettings()["adb_enabled"] == "1")
        #expect((try? String(contentsOf: r.log, encoding: .utf8))?.contains("uninstall") == true)
    }

    @Test func restorePointWrittenBeforeFirstMutation() async throws {
        let r = try rig()
        let report = try await r.engine.apply([.removePackage(a)], on: device, reason: "t")
        let calls = r.fake.calls()
        let firstMutation = try #require(calls.firstIndex { $0.contains("pm uninstall") })
        #expect(try #require(calls.firstIndex { $0.contains("settings list global") }) < firstMutation)
        #expect(try #require(calls.firstIndex { $0.contains(" pull ") }) < firstMutation)
        #expect(report.restorePoint.apks[a.value]?.isEmpty == false)
    }

    @Test func stopsOnOfflineMidApply() async throws {
        let r = try rig(["fail_after": "2"])
        let report = try await r.engine.apply([.removePackage(a), .removePackage(b), .removePackage(c), .removePackage(d)], on: device, reason: "t")
        #expect(report.applied == [.removePackage(a), .removePackage(b)])
        #expect(report.failed?.0 == .removePackage(c))
        #expect(report.failed?.1 == .offline)
        #expect(report.pending == [.removePackage(d)])
    }

    @Test func refusesHostileValuesBeforeDoingAnything() async throws {
        let r = try rig()
        for bad in [Change.setSetting(ns: .global, key: "k", value: "v; rm -rf /"),
                    .setSetting(ns: .global, key: "k k", value: "v"),
                    .setSetting(ns: .secure, key: "k", value: "$(reboot)"),
                    .revokePermission(a, "android.permission.X; reboot")] {
            await #expect(throws: ChangeError.unsafeValue) { try await r.engine.apply([bad], on: device, reason: "t") }
        }
        #expect(r.fake.calls().isEmpty)
    }

    @Test func revertDeletesSettingAbsentBefore() async throws {
        let r = try rig()
        let report = try await r.engine.apply([.setSetting(ns: .global, key: "tether_test", value: "1")], on: device, reason: "t")
        #expect(r.globalSettings()["tether_test"] == "1")
        _ = try await r.engine.revert(report.restorePoint, on: device)
        #expect(r.globalSettings()["tether_test"] == nil)
        #expect(r.globalSettings()["adb_enabled"] == "1")
    }

    @Test func revertLeavesUntouchedSettingsAlone() async throws {
        let r = try rig()
        let report = try await r.engine.apply([.setSetting(ns: .global, key: "tether_test", value: "1")], on: device, reason: "t")
        try "window_animation_scale=0.5\nadb_enabled=1\ntether_test=1\n".write(to: r.fake.dir.appendingPathComponent("settings_global.txt"), atomically: true, encoding: .utf8)
        _ = try await r.engine.revert(report.restorePoint, on: device)
        #expect(r.globalSettings()["window_animation_scale"] == "0.5")
    }

    @Test func revertRefusesOtherDevice() async throws {
        let r = try rig()
        let report = try await r.engine.apply([.removePackage(a)], on: device, reason: "t")
        let other = DeviceProfile(serial: "192.168.1.9:5555", vendor: "amazon", model: "X", androidVersion: "9", sdk: 28, abis: [], platform: .fireOS)
        let before = r.mutatingCalls().count
        await #expect(throws: ChangeError.wrongDevice) { try await r.engine.revert(report.restorePoint, on: other) }
        #expect(r.mutatingCalls().count == before)
    }

    @Test func usesSerialOnEveryCall() async throws {
        let r = try rig()
        let report = try await r.engine.apply([.removePackage(a), .setSetting(ns: .global, key: "k", value: "1")], on: device, reason: "t")
        _ = try await r.engine.revert(report.restorePoint, on: device)
        #expect(r.fake.calls().allSatisfy { $0.hasPrefix("-P 5038 -s \(device.serial) ") })
    }

    @Test func skipsAlreadyRemovedPackage() async throws {
        let r = try rig(["packages_installed.txt": "com.amazon.bravo\n"])
        let report = try await r.engine.apply([.removePackage(a)], on: device, reason: "t")
        #expect(report.applied == [.removePackage(a)])
        #expect(!r.fake.calls().contains { $0.contains("pm uninstall") })
    }

    @Test func fallsBackToPulledAPK() async throws {
        let r = try rig()
        let report = try await r.engine.apply([.removePackage(a)], on: device, reason: "t")
        try "com.amazon.bravo\ncom.amazon.charlie\ncom.amazon.delta\n".write(to: r.fake.dir.appendingPathComponent("packages_all.txt"), atomically: true, encoding: .utf8)
        let reverted = try await r.engine.revert(report.restorePoint, on: device)
        #expect(reverted.failed == nil)
        #expect(r.fake.lines("installs.log").count == 1)
        #expect(r.installed().contains(a.value))
    }

    @Test func densityRoundTrips() async throws {
        let r = try rig(["density.txt": "320"])
        let report = try await r.engine.apply([.setDensity(240)], on: device, reason: "t")
        #expect(r.fake.lines("density.txt") == ["240"])
        _ = try await r.engine.revert(report.restorePoint, on: device)
        #expect(r.fake.lines("density.txt") == ["320"])
    }
}
