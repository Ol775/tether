import Foundation
import Testing
@testable import TetherCore

struct RestorePointStoreTests {
    let device = DeviceProfile(serial: "192.168.1.5:5555", vendor: "amazon", model: "AFTMM", androidVersion: "9", sdk: 28, abis: ["armeabi-v7a"], platform: .fireOS)
    let recess = PackageName("com.amazon.recess")!

    func makeStore(_ extra: [String: String] = [:]) throws -> (RestorePointStore, FakeADB, URL) {
        let fake = try FakeADB(files: [
            "packages_all.txt": "com.amazon.recess\ncom.android.settings\ncom.amazon.gone\n",
            "packages_installed.txt": "com.amazon.recess\ncom.android.settings\n",
            "settings_global.txt": "adb_enabled=1\n",
            "settings_secure.txt": "screensaver_enabled=1\n",
            "density.txt": "240\n",
        ].merging(extra) { $1 })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rp-\(UUID().uuidString)")
        return (RestorePointStore(root: root, adb: fake.runner), fake, root)
    }

    @Test func roundTripsJSON() async throws {
        let (store, _, _) = try makeStore()
        let rp = try await store.create(device: device, reason: "test", pullAPKsFor: [])
        let loaded = try await store.load(rp.id)
        #expect(loaded == rp)
        #expect(rp.settings["global"] == ["adb_enabled": "1"])
        #expect(rp.settings["secure"] == ["screensaver_enabled": "1"])
        #expect(rp.settings["system"] == [:])
        #expect(rp.density == 240)
        #expect(rp.packages.first { $0.name.value == "com.amazon.gone" }?.state == .removedForUser)
    }

    @Test func pullsSplitAPKs() async throws {
        let (store, _, _) = try makeStore(["split_com.amazon.recess": "package:/data/app/x/split_config.apk\n"])
        let rp = try await store.create(device: device, reason: "test", pullAPKsFor: [recess])
        let urls = await store.apkURLs(rp, for: recess)
        #expect(urls.count == 2)
        #expect(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func failsWhenAPKMissing() async throws {
        let (store, _, root) = try makeStore(["pull_empty": ""])
        await #expect(throws: RestoreError.self) {
            try await store.create(device: device, reason: "test", pullAPKsFor: [recess])
        }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test func listsNewestFirst() async throws {
        let (store, _, _) = try makeStore()
        let first = try await store.create(device: device, reason: "one", pullAPKsFor: [])
        try await Task.sleep(for: .milliseconds(20))
        let second = try await store.create(device: device, reason: "two", pullAPKsFor: [])
        #expect(try await store.list().map(\.id) == [second.id, first.id])
    }
}
