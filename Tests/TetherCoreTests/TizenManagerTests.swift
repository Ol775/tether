import Foundation
import Testing
@testable import TetherCore

struct TizenManagerTests {
    func rig(_ extra: [String: String] = [:]) throws -> (FakeSDB, TizenManager) {
        let fake = try FakeSDB(files: ["capability.txt": fixture("sdb-capability-2021.txt"), "devices.txt": "192.168.1.60:26101\tdevice\tQE55Q80AAT\n"].merging(extra) { $1 })
        return (fake, TizenManager(sdb: fake.runner))
    }

    @Test func connectSucceeds() async throws {
        let (fake, m) = try rig()
        try await m.connect(host: "192.168.1.60")
        #expect(fake.calls().first == "connect 192.168.1.60:26101")
    }

    @Test func connectFailureTextBecomesRefusedEvenWithExitZero() async throws {
        let (_, m) = try rig(["connect_result": "failed to connect to remote target 192.168.1.60:26101\n"])
        await #expect(throws: SDBError.refused) { try await m.connect(host: "192.168.1.60") }
    }

    @Test func alreadyConnectedCounts() async throws {
        let (_, m) = try rig(["connect_result": "already connected to 192.168.1.60:26101\n"])
        try await m.connect(host: "192.168.1.60")
    }

    @Test func offlineAndUnauthorizedDevicesAreSkipped() async throws {
        let (_, m) = try rig(["devices.txt": fixture("sdb-devices.txt")])
        let found = try await m.devices()
        #expect(found.map(\.serial) == ["192.168.1.60:26101"] && found.first?.modelYear == 2021)
    }

    @Test func hostileHostRejectedBeforeAnyCall() async throws {
        let (fake, m) = try rig()
        await #expect(throws: DeviceError.invalidHost) { try await m.connect(host: "tv;rm -rf /") }
        #expect(fake.calls().isEmpty)
    }

    @Test func preTwentyNineteenTVIsRefusedAndDisconnected() async throws {
        let (fake, m) = try rig(["capability.txt": "model_name:UN55NU8000\nplatform_version:4.0\n"])
        await #expect(throws: TizenError.unsupportedModel(year: 2018)) { try await m.connect(host: "192.168.1.60") }
        #expect(fake.calls().contains { $0.hasPrefix("disconnect ") })
    }

    @Test func listingDropsUnsupportedModels() async throws {
        let (_, m) = try rig(["capability.txt": "model_name:UN55NU8000\n"])
        #expect(try await m.devices().isEmpty)
    }
}
