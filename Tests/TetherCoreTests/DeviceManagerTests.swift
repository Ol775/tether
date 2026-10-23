import Testing
@testable import TetherCore

struct DeviceManagerTests {
    @Test func connectSucceeds() async throws {
        let fake = try FakeADB()
        try await DeviceManager(adb: fake.runner).connect(host: "192.168.1.5", port: 5555)
        #expect(fake.calls() == ["-P 5038 connect 192.168.1.5:5555"])
    }

    @Test func connectUnauthorizedThrows() async throws {
        let fake = try FakeADB(files: ["connect_result": "failed to authenticate to 192.168.1.5:5555\n"])
        await #expect(throws: ADBError.unauthorized) {
            try await DeviceManager(adb: fake.runner).connect(host: "192.168.1.5")
        }
    }

    @Test func connectFailureThrows() async throws {
        let fake = try FakeADB(files: ["connect_result": "failed to connect to '192.168.1.5:5555': Connection refused\n"])
        await #expect(throws: ADBError.self) {
            try await DeviceManager(adb: fake.runner).connect(host: "192.168.1.5")
        }
    }

    @Test func devicesReturnsProfilesWithSerialQualifiedCalls() async throws {
        let fake = try FakeADB(files: [
            "devices.txt": "192.168.1.5:5555 device model:AFTMM\n192.168.1.6:5555 device model:AFTMM\nR5CT unauthorized\n",
            "props.txt": "ro.product.manufacturer=Amazon\nro.product.model=AFTMM\nro.build.version.sdk=28\n",
        ])
        let profiles = try await DeviceManager(adb: fake.runner).devices()
        #expect(profiles.map(\.serial) == ["192.168.1.5:5555", "192.168.1.6:5555"])
        let getprops = fake.calls().filter { $0.hasSuffix("getprop") }
        #expect(getprops.count == 2)
        #expect(getprops.allSatisfy { $0.contains(" -s ") })
    }

    @Test func rejectsBadHostAndPort() async throws {
        let fake = try FakeADB()
        let dm = DeviceManager(adb: fake.runner)
        for bad in ["192.168.1.5; rm", "a b", "", "-x", "host\nname"] {
            await #expect(throws: DeviceError.invalidHost) { try await dm.connect(host: bad) }
        }
        await #expect(throws: DeviceError.invalidHost) { try await dm.connect(host: "192.168.1.5", port: 70000) }
        #expect(fake.calls().isEmpty)
    }

    @Test func pairRejectsBadCode() async throws {
        let fake = try FakeADB()
        await #expect(throws: DeviceError.invalidPairingCode) {
            try await DeviceManager(adb: fake.runner).pair(host: "192.168.1.5", port: 37000, code: "12 34")
        }
    }

    @Test func pairSucceeds() async throws {
        let fake = try FakeADB()
        try await DeviceManager(adb: fake.runner).pair(host: "192.168.1.5", port: 37000, code: "123456")
        #expect(fake.calls() == ["-P 5038 pair 192.168.1.5:37000 123456"])
    }
}
