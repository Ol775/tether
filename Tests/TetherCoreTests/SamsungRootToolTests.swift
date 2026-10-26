import Foundation
import Testing
@testable import TetherCore

struct SamsungRootToolTests {
    private let device = TizenDevice(serial: "192.0.2.40:26101", model: "TestTV", modelYear: 2021,
                                     tizenVersion: "6.0", shellEnabled: false, rootAvailable: false)

    private struct Rig {
        let directory: URL
        let executable: URL
        func calls() throws -> String { try String(contentsOf: directory.appendingPathComponent("calls"), encoding: .utf8) }
    }

    private func rig(version: String = "0.0.12", command: String = "id", changes: [String: Any] = [:], exit: Int = 0) throws -> Rig {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("root-tool-test \(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fake-root-tool")
        // Deliberately a stand-in: no SDB, networking, payloads or exploit code is run by these tests.
        let script = """
        #!/bin/bash
        D=$(cd "$(dirname "$0")" && pwd)
        printf '%s\\n' "$@" >> "$D/calls"
        if [[ "$1" == --version ]]; then cat "$D/version"; exit 0; fi
        if [[ "${@: -1}" == doctor ]]; then echo 'local setup only'; exit 0; fi
        cat "$D/result.json"
        exit \(exit)
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try version.write(to: directory.appendingPathComponent("version"), atomically: true, encoding: .utf8)
        var evidence: [String: Any] = ["host": "192.0.2.40", "authenticated": true, "uid": 0, "euid": 0,
            "system_files_unchanged": true, "staging_cleaned": true,
            "commands": [["command": command, "stdout": "uid=0(root)", "stderr": "", "exit_code": exit, "timed_out": false]]]
        evidence.merge(changes) { _, new in new }
        try JSONSerialization.data(withJSONObject: evidence).write(to: directory.appendingPathComponent("result.json"))
        return Rig(directory: directory, executable: executable)
    }

    private func request(_ rig: Rig, command: String = "id", callback: String = "192.0.2.5") throws -> SamsungRootRequest {
        try SamsungRootRequest(tool: rig.executable, sdb: URL(fileURLWithPath: "/usr/bin/true"),
                               device: device, callback: callback, command: command)
    }

    @Test func noToolRunsWithoutConfirmation() async throws {
        let rig = try rig()
        let request = try request(rig)
        await #expect(throws: SamsungRootError.self) { _ = try await SamsungRootTool.run(request) }
        #expect(!FileManager.default.fileExists(atPath: rig.directory.appendingPathComponent("calls").path))
    }

    @Test func localSetupNeverInvokesAnExploitOrTarget() async throws {
        let rig = try rig()
        let report = try await SamsungRootTool.checkLocalInstallation(tool: rig.executable, sdb: URL(fileURLWithPath: "/usr/bin/true"))
        #expect(report.contains("local setup only"))
        let calls = try rig.calls()
        #expect(calls.contains("doctor"))
        #expect(!calls.contains("archive-root"))
        #expect(!calls.contains("192.0.2.40"))
    }

    @Test func confirmsIdentityAndCleanupForExactlyTheRequestedTarget() async throws {
        let rig = try rig()
        let result = try await SamsungRootTool.run(request(rig), confirmed: true)
        #expect(result.stdout == "uid=0(root)")
        #expect(result.exitCode == 0)
        #expect(result.deviceSerial == device.serial)
        #expect(try rig.calls().contains("--bind-host\n192.0.2.5"))
    }

    @Test func remoteShellSyntaxNeverExecutesOnTheMac() async throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("must-not-exist-\(UUID())")
        let command = "echo $(touch '\(marker.path)'); id"
        let rig = try rig(command: command)
        let result = try await SamsungRootTool.run(request(rig, command: command), confirmed: true)
        #expect(result.command == command)
        #expect(try rig.calls().contains("--command\n" + command))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func rejectsUnauthenticatedOrUncleanResults() async throws {
        for changes: [String: Any] in [["authenticated": false], ["uid": 901], ["euid": 901],
                                       ["staging_cleaned": false], ["system_files_unchanged": false], ["host": "192.0.2.99"]] {
            let rig = try rig(changes: changes)
            await #expect(throws: SamsungRootError.self) { _ = try await SamsungRootTool.run(request(rig), confirmed: true) }
        }
    }

    @Test func rejectsEvidenceForADifferentCommand() async throws {
        let rig = try rig(command: "echo something-else")
        await #expect(throws: SamsungRootError.self) { _ = try await SamsungRootTool.run(request(rig), confirmed: true) }
    }

    @Test func nonzeroCommandExitIsPreservedAfterVerifiedCleanup() async throws {
        let rig = try rig(exit: 7)
        let result = try await SamsungRootTool.run(request(rig), confirmed: true)
        #expect(result.exitCode == 7)
    }

    @Test func unreviewedToolVersionStopsBeforeRoot() async throws {
        let rig = try rig(version: "0.9.0")
        await #expect(throws: SamsungRootError.self) { _ = try await SamsungRootTool.run(request(rig), confirmed: true) }
        #expect(try rig.calls() == "--version\n")
    }

    @Test func rejectsInvalidTargetAndCallbackBeforeExecution() throws {
        let rig = try rig()
        #expect(throws: (any Error).self) { _ = try request(rig, callback: "0.0.0.0") }
        #expect(throws: (any Error).self) { _ = try request(rig, callback: "192.0.2.5;id") }
        let wrongPort = TizenDevice(serial: "192.0.2.40:1234", model: "TestTV", modelYear: 2021,
                                   tizenVersion: "6.0", shellEnabled: false, rootAvailable: false)
        #expect(throws: (any Error).self) {
            _ = try SamsungRootRequest(tool: rig.executable, sdb: URL(fileURLWithPath: "/usr/bin/true"),
                                       device: wrongPort, callback: "192.0.2.5", command: "id")
        }
    }

    @Test func rejectsMissingPayloadOverride() throws {
        let rig = try rig()
        #expect(throws: (any Error).self) {
            _ = try SamsungRootRequest(tool: rig.executable, sdb: URL(fileURLWithPath: "/usr/bin/true"), device: device,
                                       callback: "192.0.2.5", command: "id", payloads: rig.directory)
        }
    }
}
