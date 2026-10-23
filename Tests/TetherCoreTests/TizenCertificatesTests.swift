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

    @Test func emptyRealCLITableIsMissing() async throws {
        let listing = "Loaded in '/some/profile/profiles.xml'.\n========================\nName\n========================\n"
        #expect(await TizenCertificates(tools: try tools(listing: listing)).state(for: tv) == .missing)
    }

    @Test func installedSDKEmptyTableIsMissing() async throws {
        let listing = "Loaded in '/some/profile/profiles.xml'.\n[Profile Name]      [Active]  \n"
        #expect(await TizenCertificates(tools: try tools(listing: listing)).state(for: tv) == .missing)
    }

    @Test func namedRealCLIProfileIsAvailable() async throws {
        let listing = "Loaded in '/some/profile/profiles.xml'.\n========================\nName\n========================\nSamsungTV\n"
        #expect(await TizenCertificates(tools: try tools(listing: listing)).state(for: tv) == .unknown)
    }

    @Test func cliFailureIsNotMistakenForMissingCertificate() async throws {
        let tools = try tools(listing: "")
        let cli = try #require(tools.tizenCLI)
        try "#!/bin/sh\nexit 1\n".write(to: cli, atomically: true, encoding: .utf8)
        #expect(await TizenCertificates(tools: tools).state(for: tv) == .checkFailed)
    }

    @Test func profileXMLMustContainANamedProfile() {
        #expect(TizenCertificates.containsProfiles(Data("<profiles><profile name=\"SamsungTV\"/></profiles>".utf8)))
        #expect(!TizenCertificates.containsProfiles(Data("<profiles/>".utf8)))
        #expect(!TizenCertificates.containsProfiles(Data("<profiles><profile name=\"\"/></profiles>".utf8)))
        #expect(!TizenCertificates.containsProfiles(Data("not XML".utf8)))
        #expect(!TizenCertificates.containsProfiles(Data("<!DOCTYPE profiles SYSTEM \"file:///etc/passwd\"><profiles/>".utf8)))
    }

    @Test func selectsProfilePathWithSpacesAsOneArgument() async throws {
        let tools = try tools(listing: "")
        let cli = try #require(tools.tizenCLI)
        let directory = cli.deletingLastPathComponent()
        let profile = directory.appendingPathComponent("My Profiles.xml")
        let log = directory.appendingPathComponent("arguments.txt")
        try "<profiles><profile name=\"SamsungTV\"/></profiles>".write(to: profile, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$(dirname \"$0\")/arguments.txt\"\n".write(to: cli, atomically: true, encoding: .utf8)
        try await TizenCertificates(tools: tools).useProfilesFile(profile)
        let args = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(args == ["cli-config", "-g", "default.profiles.path=\(profile.path)"])
    }

    @Test func everyStateHasPlainAdvice() {
        for s in [CertificateState.ready, .missing, .notForThisTV, .toolsMissing, .unknown, .checkFailed] { #expect(!s.advice.isEmpty) }
    }
}
