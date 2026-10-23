import Foundation
import Testing
@testable import TetherCore

struct TizenCertificatesTests {
    let tv = TizenDevice(serial: "s:1", deviceID: "DUIDTESTVALUE123", model: "QE55Q80AAT", modelYear: 2021, tizenVersion: "6.0", shellEnabled: false, rootAvailable: false)

    /// Tools folder whose `tizen` prints `listing` for any arguments.
    func tools(listing: String?) throws -> SamsungTools {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("certs-\(UUID().uuidString)")
        guard let listing else { return SamsungTools(home: home) }
        let bin = home.appendingPathComponent("tizen-studio/tools/ide/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        for (path, body) in [(home.appendingPathComponent("tizen-studio/tools/sdb"), "#!/bin/bash\n"),
                             (bin.appendingPathComponent("tizen"), "#!/bin/bash\ncat <<'EOF'\n\(listing)\nEOF\n")] {
            try body.write(to: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        }
        return SamsungTools(home: home)
    }

    @Test func toolsMissingWithoutTools() async throws {
        #expect(await TizenCertificates(tools: try tools(listing: nil)).state(for: tv) == .toolsMissing)
    }

    @Test func missingWhenNoProfile() async throws {
        #expect(await TizenCertificates(tools: try tools(listing: "")).state(for: tv) == .missing)
    }

    @Test func readyWhenProfileListsThisTVsDUID() async throws {
        let listing = "# ASSUMED FORMAT\nprofile: Tether (active)\n  duid: OTHER456, DUIDTESTVALUE123"
        #expect(await TizenCertificates(tools: try tools(listing: listing)).state(for: tv) == .ready)
    }

    @Test func notForThisTVWhenOnlyOtherDUIDsAreListed() async throws {
        let listing = "profile: Tether (active)\n  duid: OTHER456"
        #expect(await TizenCertificates(tools: try tools(listing: listing)).state(for: tv) == .notForThisTV)
    }

    @Test func unknownWhenAProfileExistsButShowsNoDUIDs() async throws {
        #expect(await TizenCertificates(tools: try tools(listing: "profile: Tether (active)")).state(for: tv) == .unknown)
    }

    @Test func everyStateHasPlainAdvice() {
        for s in [CertificateState.ready, .missing, .notForThisTV, .toolsMissing, .unknown] { #expect(!s.advice.isEmpty) }
    }
}
