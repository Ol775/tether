import Foundation
import Testing
@testable import TetherCore

struct TweakTests {
    let fireTV = DeviceProfile(serial: "192.168.1.5:5555", vendor: "amazon", model: "AFTMM", androidVersion: "9", sdk: 28, abis: [], platform: .fireOS)

    func snapshot(global: [String: String] = [:], density: Int? = nil, physical: Int? = 320) -> DeviceSnapshot {
        DeviceSnapshot(packages: [], settings: ["global": global, "secure": [:], "system": [:]], density: density, home: nil, physicalDensity: physical)
    }

    func tweak(_ id: String, _ platform: Platform = .android, _ snap: DeviceSnapshot? = nil) -> Tweak {
        TweakLibrary.available(for: platform, snapshot: snap ?? snapshot()).first { $0.id == id }!
    }

    @Test func animationOffProducesThreeSettings() {
        let off = tweak("animations").options.first { $0.label == "Off" }!
        #expect(off.changes == [
            .setSetting(ns: .global, key: "window_animation_scale", value: "0"),
            .setSetting(ns: .global, key: "transition_animation_scale", value: "0"),
            .setSetting(ns: .global, key: "animator_duration_scale", value: "0"),
        ])
    }

    @Test func currentOptionMatchesAppliedValues() {
        let zeros = ["window_animation_scale": "0", "transition_animation_scale": "0", "animator_duration_scale": "0"]
        let snap = snapshot(global: zeros)
        #expect(TweakLibrary.currentOption(for: tweak("animations", .android, snap), in: snap)?.label == "Off")
        let odd = snapshot(global: ["window_animation_scale": "3"])
        #expect(TweakLibrary.currentOption(for: tweak("animations"), in: odd) == nil)
    }

    @Test func densityOptionsScaleFromPhysical() {
        let options = tweak("density").options
        #expect(options.map(\.label) == ["Default", "Larger UI (−15%)", "Smaller UI (+15%)", "Smaller UI (+30%)"])
        #expect(options.map(\.changes) == [[.setDensity(nil)], [.setDensity(272)], [.setDensity(368)], [.setDensity(416)]])
        #expect(!TweakLibrary.available(for: .android, snapshot: snapshot(physical: nil)).contains { $0.id == "density" })
    }

    @Test func densityDefaultIsCurrentWithoutOverride() {
        let snap = snapshot(density: nil)
        #expect(TweakLibrary.currentOption(for: tweak("density", .android, snap), in: snap)?.label == "Default")
    }

    @Test func fireOSOnlyTweaksHiddenOnPixel() {
        let android = TweakLibrary.available(for: .android, snapshot: snapshot()).map(\.id)
        let fire = TweakLibrary.available(for: .fireOS, snapshot: snapshot()).map(\.id)
        #expect(!android.contains("limit-ad-tracking") && fire.contains("limit-ad-tracking"))
        #expect(!fire.contains("screen-timeout"))
    }

    @Test func everyTweakOptionRevertsViaRestorePoint() async throws {
        let original = ["settings_global.txt": "window_animation_scale=1.0\nadb_enabled=1\n", "settings_system.txt": "screen_off_timeout=60000\n"]
        for platform in [Platform.android, .fireOS] {
            let probe = try FakeADB(files: original)
            let snap = try await DeviceSnapshot.capture(adb: probe.runner, serial: "s")
            for tweak in TweakLibrary.available(for: platform, snapshot: snap) {
                for option in tweak.options {
                    let fake = try FakeADB(files: original)
                    let root = FileManager.default.temporaryDirectory.appendingPathComponent("tw-\(UUID())")
                    let engine = ChangeEngine(adb: fake.runner, store: RestorePointStore(root: root, adb: fake.runner), log: ChangeLog(file: root.appendingPathComponent("log")))
                    let device = DeviceProfile(serial: "s", vendor: "x", model: "m", androidVersion: "9", sdk: 28, abis: [], platform: platform)
                    let before = try await DeviceSnapshot.capture(adb: fake.runner, serial: "s")
                    let report = try await engine.apply(option.changes, on: device, reason: option.label)
                    #expect(report.verified, "\(tweak.id)/\(option.label)")
                    do { _ = try await engine.revert(report.restorePoint, on: device) } catch ChangeError.empty {}   // option was already current
                    let after = try await DeviceSnapshot.capture(adb: fake.runner, serial: "s")
                    #expect(after.settings == before.settings && after.density == before.density, "\(tweak.id)/\(option.label)")
                }
            }
        }
    }

    @Test func absurdPhysicalDensityDropsTheTweakInsteadOfCrashing() {
        for hostile in [Int.max, 9_000_000_000_000_000_000, 50, 5000, 0, -1] {
            let ids = TweakLibrary.available(for: .android, snapshot: snapshot(physical: hostile)).map(\.id)
            #expect(!ids.contains("density"), "\(hostile)")
        }
    }
}
