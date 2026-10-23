import Foundation
import Testing
@testable import TetherCore

struct ProcessRunnerTests {
    @Test func cancellingAlsoStopsGrandchildProcesses() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("grandchild-\(UUID().uuidString)")
        let script = "sleep 60 & echo $! > '\(pidFile.path)'; wait"
        let task = Task { try await ProcessRunner.run(URL(fileURLWithPath: "/bin/bash"), ["-c", script], timeout: .seconds(60)) }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: pidFile.path) { try await Task.sleep(for: .milliseconds(20)) }
        let pid = try #require(pid_t((try String(contentsOf: pidFile, encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines)))
        task.cancel()
        _ = try? await task.value
        for _ in 0..<100 where kill(pid, 0) == 0 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(kill(pid, 0) != 0)
    }
}
