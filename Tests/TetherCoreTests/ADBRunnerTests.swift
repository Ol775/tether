import Foundation
import Testing
@testable import TetherCore

struct ADBRunnerTests {
    @Test func passesPortAndSerial() async throws {
        let fake = try FakeADB()
        _ = try await fake.runner.run(["devices"], serial: "192.168.1.5:5555")
        #expect(fake.calls().first == "-P 5038 -s 192.168.1.5:5555 devices")
    }

    @Test func timesOut() async throws {
        let fake = try FakeADB(files: ["sleep": "5"])
        await #expect(throws: ADBError.timeout) {
            try await fake.runner.run(["devices"], timeout: .milliseconds(300))
        }
    }

    @Test func mapsUnauthorized() async throws {
        let fake = try FakeADB(files: ["force_error": "error: device unauthorized.\n"])
        await #expect(throws: ADBError.unauthorized) {
            try await fake.runner.run(["devices"])
        }
    }

    @Test func missingBinary() async {
        let runner = ADBRunner(executable: URL(fileURLWithPath: "/nonexistent/adb"))
        await #expect(throws: ADBError.adbMissing) {
            try await runner.run(["devices"])
        }
    }
}
