import Foundation
import Testing
@testable import TetherCore

struct SDBRunnerTests {
    @Test func passesSerial() async throws {
        let fake = try FakeSDB()
        _ = try await fake.runner.run(["devices"], serial: "192.168.1.60:26101")
        #expect(fake.calls().first == "-s 192.168.1.60:26101 devices")
    }

    @Test func timesOut() async throws {
        let fake = try FakeSDB(files: ["sleep": "5"])
        await #expect(throws: SDBError.timeout) { try await fake.runner.run(["devices"], timeout: .milliseconds(300)) }
    }

    @Test func missingBinaryIsToolsMissing() async throws {
        let runner = SDBRunner(executable: URL(fileURLWithPath: "/nonexistent/sdb"))
        await #expect(throws: SDBError.toolsMissing) { try await runner.run(["devices"]) }
    }

    @Test func classifiesRefusedAndNotConnected() async throws {
        let refused = try FakeSDB(files: ["force_error": "failed to connect to remote target 192.168.1.60:26101\n"])
        await #expect(throws: SDBError.refused) { try await refused.runner.run(["connect", "x"]) }
        let closed = try FakeSDB(files: ["force_error": "error: closed\n"])
        await #expect(throws: SDBError.notConnected) { try await closed.runner.run(["devices"]) }
    }

    @Test func aMissingShellCommandIsNotReportedAsADisconnect() {
        #expect(SDBError.classify(code: 1, output: "sh: vd_appuninstall: not found") == .commandFailed(code: 1, output: "sh: vd_appuninstall: not found"))
        #expect(SDBError.classify(code: 1, output: "error: device '192.168.1.60:26101' not found") == .notConnected)
    }
}
