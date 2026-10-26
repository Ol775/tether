import Foundation
import Testing
@testable import TetherCore

struct ConnectionDiagnosticsTests {
    let endpoint = try! ConnectionEndpoint(address: "192.168.1.18", port: "26101")

    private func status(mode: String = "1", host: String = "192.168.1.41") throws -> SamsungConnectionStatus {
        try JSONDecoder().decode(SamsungConnectionStatus.self,
            from: Data("{\"developerMode\":\"\(mode)\",\"developerIP\":\"\(host)\",\"modelName\":\"Test TV\",\"PowerState\":\"on\"}".utf8))
    }

    @Test func reachablePortDoesNotClaimAWorkingSession() async throws {
        let fake = try FakeSDB()
        let adb = try FakeADB()
        let info = try status()
        let report = try await ConnectionDiagnostics.run(service: .sdb, endpoint: endpoint,
            localAddresses: ["192.168.1.41"], adb: adb.runner, sdb: fake.runner,
            probe: { _ in .open }, status: { _ in info })
        #expect(report.checks.first { $0.id == "port" }?.status == .passed)
        #expect(report.checks.first { $0.id == "session" }?.status == .warning)
        #expect(report.nextStep.contains("Restart the SDB"))
        #expect(fake.calls() == ["devices"])
    }

    @Test func connectedTVRequiresReadableCapabilities() async throws {
        let fake = try FakeSDB(files: ["devices.txt": "192.168.1.18:26101\tdevice\tTestTV\n", "capability.txt": "platform_version:6.0\n"])
        let adb = try FakeADB()
        let info = try status()
        let report = try await ConnectionDiagnostics.run(service: .sdb, endpoint: endpoint,
            localAddresses: ["192.168.1.41"], adb: adb.runner, sdb: fake.runner,
            probe: { _ in .open }, status: { _ in info })
        #expect(report.nextStep.contains("session is working"))
        #expect(fake.calls() == ["devices", "-s 192.168.1.18:26101 capability"])
        #expect(adb.calls().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fake.dir.appendingPathComponent("mutations").path))
    }

    @Test func hostMismatchAndDisabledModeHaveSpecificAdvice() async throws {
        let fake = try FakeSDB()
        let adb = try FakeADB()
        let info = try status(mode: "0", host: "192.168.1.99")
        let report = try await ConnectionDiagnostics.run(service: .sdb, endpoint: endpoint,
            localAddresses: ["192.168.1.41"], adb: adb.runner, sdb: fake.runner,
            probe: { _ in .open }, status: { _ in info })
        #expect(report.checks.first { $0.id == "developer" }?.status == .failed)
        #expect(report.nextStep.contains("Host PC IP"))
    }

    @Test func anyActiveMacInterfaceCanMatchTheTVHost() async throws {
        let fake = try FakeSDB()
        let adb = try FakeADB()
        let info = try status()
        let report = try await ConnectionDiagnostics.run(service: .sdb, endpoint: endpoint,
            localAddresses: ["10.0.0.2", "192.168.1.41"], adb: adb.runner, sdb: fake.runner,
            probe: { _ in .open }, status: { _ in info })
        #expect(report.checks.first { $0.id == "developer" }?.status == .passed)
    }

    @Test func missingHTTPStatusDoesNotDeclareTheTVOffline() async throws {
        let fake = try FakeSDB()
        let adb = try FakeADB()
        let report = try await ConnectionDiagnostics.run(service: .sdb, endpoint: endpoint,
            localAddresses: ["192.168.1.41"], adb: adb.runner, sdb: fake.runner,
            probe: { _ in .open }, status: { _ in throw URLError(.timedOut) })
        #expect(report.checks.first { $0.id == "tv" }?.status == .warning)
        #expect(report.nextStep.contains("Restart the SDB"))
    }

    @Test func unreachablePortGivesNetworkAdvice() async throws {
        let fake = try FakeSDB()
        let adb = try FakeADB()
        let report = try await ConnectionDiagnostics.run(service: .sdb, endpoint: endpoint,
            localAddresses: [], adb: adb.runner, sdb: fake.runner,
            probe: { _ in .timedOut }, status: { _ in throw URLError(.timedOut) })
        #expect(report.nextStep.contains("access point"))
        #expect(report.checks.first { $0.id == "port" }?.status == .failed)
    }

    @Test func cancellationStopsBeforeDebugCommands() async throws {
        let fake = try FakeSDB()
        let adb = try FakeADB()
        await #expect(throws: CancellationError.self) {
            _ = try await ConnectionDiagnostics.run(service: .sdb, endpoint: endpoint,
                localAddresses: [], adb: adb.runner, sdb: fake.runner, probe: { _ in .cancelled })
        }
        #expect(fake.calls().isEmpty)
    }

    @Test func samsungStatusReadsOnlyConnectionFields() async throws {
        let host = "status-test.local"
        let url = URL(string: "http://\(host):8001/api/v2/")!
        StubURLProtocol.stub(url, .init(status: 200, body: Data("""
        {"device":{"developerMode":"1","developerIP":"192.168.1.41","modelName":"Test TV","PowerState":"on","duid":"do-not-export","token":"do-not-export"}}
        """.utf8)))
        let info = try await ConnectionDiagnostics.samsungStatus(host: host, session: StubURLProtocol.session)
        #expect(info.developerIP == "192.168.1.41")
        #expect(info.developerMode == "1")
        let fake = try FakeSDB()
        let adb = try FakeADB()
        let report = try await ConnectionDiagnostics.run(service: .sdb, endpoint: endpoint,
            localAddresses: ["192.168.1.41"], adb: adb.runner, sdb: fake.runner, probe: { _ in .open }, status: { _ in info })
        #expect(!report.text.contains("do-not-export"))
    }

    @Test func serviceRestartsAreScopedAndVerified() async throws {
        let sdb = try FakeSDB()
        let adb = try FakeADB()
        try await sdb.runner.restartServer()
        try await adb.runner.restartServer()
        #expect(sdb.calls() == ["kill-server", "start-server", "devices"])
        #expect(adb.calls() == ["-P 5038 kill-server", "-P 5038 start-server", "-P 5038 devices"])
    }

    @Test func failedRestartStopsAndReleasesTheRunner() async throws {
        let fake = try FakeSDB(files: ["force_error": "restart failed"])
        await #expect(throws: (any Error).self) { try await fake.runner.restartServer() }
        #expect(fake.calls() == ["kill-server"])
        try FileManager.default.removeItem(at: fake.dir.appendingPathComponent("force_error"))
        _ = try await fake.runner.run(["devices"])
        #expect(fake.calls().last == "devices")
    }
}
