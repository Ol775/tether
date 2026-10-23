import CryptoKit
import Foundation
import Testing
@testable import TetherCore

struct SamsungToolsTests {
    static let goodInstaller = """
    #!/bin/bash
    [[ "$1" == "--accept-license" ]] || exit 3
    root="$2"
    mkdir -p "$root/tools/ide/bin" "$root/package-manager"
    printf '#!/bin/bash\\necho sdb\\n' > "$root/tools/sdb"; chmod +x "$root/tools/sdb"
    printf '#!/bin/bash\\necho tizen\\n' > "$root/tools/ide/bin/tizen"; chmod +x "$root/tools/ide/bin/tizen"
    printf '#!/bin/bash\\necho "$@" >> "$(dirname "$0")/pm.log"\\n' > "$root/package-manager/package-manager-cli.bin"; chmod +x "$root/package-manager/package-manager-cli.bin"
    """

    func home() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("samsung-\(UUID().uuidString)") }

    static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }

    func tools(script: String, status: Int = 200, home: URL? = nil, pin: String? = nil) -> (SamsungTools, URL, URL) {
        let url = URL(string: "https://download.example.test/\(UUID().uuidString)/installer.bin")!
        StubURLProtocol.stub(url, .init(status: status, body: Data(script.utf8)))
        let h = home ?? self.home()
        return (SamsungTools(home: h, session: StubURLProtocol.session, installerURL: url, expectedSHA256: pin ?? Self.digest(script)), h, url)
    }

    @Test func refusesWithoutLicense() async throws {
        let (t, h, _) = tools(script: Self.goodInstaller)
        await #expect(throws: SamsungToolsError.licenseNotAccepted) { try await t.install(acceptingLicense: false) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: h.path))
    }

    @Test func refusesPlainHTTP() async throws {
        let t = SamsungTools(home: home(), session: StubURLProtocol.session, installerURL: URL(string: "http://download.example.test/i.bin")!, expectedSHA256: "x")
        await #expect(throws: SamsungToolsError.insecureURL) { try await t.install(acceptingLicense: true) { _ in } }
    }

    @Test func successfulRunExposesToolPaths() async throws {
        let (t, h, _) = tools(script: Self.goodInstaller)
        #expect(!t.isInstalled)
        try await t.install(acceptingLicense: true) { _ in }
        #expect(t.isInstalled && t.sdb?.lastPathComponent == "sdb" && t.tizenCLI?.lastPathComponent == "tizen")
        let log = try String(contentsOf: h.appendingPathComponent("tizen-studio/package-manager/pm.log"), encoding: .utf8)
        #expect(log.contains("install --accept-license cert-add-on"))
        #expect(!FileManager.default.fileExists(atPath: h.appendingPathComponent(".incomplete").path))
    }

    @Test func failedInstallerLeavesNothingUsable() async throws {
        let (t, h, _) = tools(script: "#!/bin/bash\nmkdir -p \"$2/tools\"; echo half > \"$2/tools/sdb\"; echo boom >&2; exit 1\n")
        await #expect(throws: SamsungToolsError.installerFailed(code: 1, output: "boom")) { try await t.install(acceptingLicense: true) { _ in } }
        #expect(!t.isInstalled && !FileManager.default.fileExists(atPath: h.appendingPathComponent("tizen-studio").path))
    }

    @Test func badDownloadStatusInstallsNothing() async throws {
        let (t, h, _) = tools(script: "not found", status: 500)
        await #expect(throws: SamsungToolsError.downloadFailed(status: 500)) { try await t.install(acceptingLicense: true) { _ in } }
        #expect(!t.isInstalled && !FileManager.default.fileExists(atPath: h.appendingPathComponent("tizen-studio").path))
    }

    @Test func interruptedRunIsRetriedCleanly() async throws {
        let h = home()
        let stale = h.appendingPathComponent("tizen-studio/tools")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try "#!/bin/bash\n".write(to: stale.appendingPathComponent("sdb"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stale.appendingPathComponent("sdb").path)
        try "leftover".write(to: stale.appendingPathComponent("leftover.txt"), atomically: true, encoding: .utf8)
        try Data().write(to: h.appendingPathComponent(".incomplete"))
        let (t, _, _) = tools(script: Self.goodInstaller, home: h)
        #expect(!t.isInstalled)   // marker blocks use even though sdb exists
        try await t.install(acceptingLicense: true) { _ in }
        #expect(t.isInstalled && !FileManager.default.fileExists(atPath: stale.appendingPathComponent("leftover.txt").path))
    }

    @Test func aDownloadThatDoesNotMatchThePinIsNeverRun() async throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("ran-\(UUID().uuidString)")
        let (t, h, _) = tools(script: "#!/bin/bash\ntouch '\(marker.path)'\n", pin: String(repeating: "0", count: 64))
        await #expect(throws: SamsungToolsError.checksumMismatch) { try await t.install(acceptingLicense: true) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: marker.path) && !t.isInstalled)
        #expect(!FileManager.default.fileExists(atPath: h.appendingPathComponent("tizen-studio").path))
    }

    @Test func redirectsToPlainHTTPOrAnotherHostAreRefused() async throws {
        for target in ["http://download.example.test/evil.bin", "https://elsewhere.example.test/evil.bin"] {
            let evil = URL(string: target)!
            StubURLProtocol.stub(evil, .init(status: 200, body: Data(Self.goodInstaller.utf8)))
            let start = URL(string: "https://download.example.test/\(UUID().uuidString)/installer.bin")!
            StubURLProtocol.stub(start, .init(status: 302, body: Data(), headers: ["Location": target]))
            let t = SamsungTools(home: home(), session: StubURLProtocol.session, installerURL: start, expectedSHA256: Self.digest(Self.goodInstaller))
            await #expect(throws: SamsungToolsError.downloadFailed(status: 302)) { try await t.install(acceptingLicense: true) { _ in } }
            #expect(!t.isInstalled)
        }
    }

    @Test func aSameHostHTTPSRedirectIsFollowed() async throws {
        let final = URL(string: "https://download.example.test/\(UUID().uuidString)/real.bin")!
        StubURLProtocol.stub(final, .init(status: 200, body: Data(Self.goodInstaller.utf8)))
        let start = URL(string: "https://download.example.test/\(UUID().uuidString)/installer.bin")!
        StubURLProtocol.stub(start, .init(status: 302, body: Data(), headers: ["Location": final.absoluteString]))
        let t = SamsungTools(home: home(), session: StubURLProtocol.session, installerURL: start, expectedSHA256: Self.digest(Self.goodInstaller))
        try await t.install(acceptingLicense: true) { _ in }
        #expect(t.isInstalled)
    }
}
