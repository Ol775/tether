import CryptoKit
import Foundation
import Testing
@testable import TetherCore

struct UpdateInstallerTests {
    let key = Curve25519.Signing.PrivateKey()
    var pub: String { key.publicKey.rawRepresentation.base64EncodedString() }

    func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("upd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A real, ad-hoc signed `Tether.app` zipped with ditto, like the release script produces.
    func makeZip(bundleID: String = "io.github.ol775.tether", version: String = "0.2.0", codesign: Bool = true, marker: String = "new") async throws -> Data {
        let dir = try scratch()
        let app = dir.appendingPathComponent("Tether.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version, "CFBundleExecutable": "Tether", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let exe = app.appendingPathComponent("Contents/MacOS/Tether")
        try "#!/bin/bash\n".write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        try marker.write(to: app.appendingPathComponent("Contents/marker.txt"), atomically: true, encoding: .utf8)
        if codesign { _ = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/codesign"), ["--force", "--deep", "-s", "-", app.path], timeout: .seconds(60)) }
        let zip = dir.appendingPathComponent("Tether.zip")
        _ = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-c", "-k", "--keepParent", app.path, zip.path], timeout: .seconds(60))
        return try Data(contentsOf: zip)
    }

    struct Rig { let installer: UpdateInstaller; let info: UpdateInfo; let work: URL }

    func rig(zip: Data, version: String = "0.2.0", signWith: Curve25519.Signing.PrivateKey? = nil, sha: String? = nil, signed: Bool = true,
             maxBytes: Int64 = 100_000_000, zipStatus: Int = 200, zipHeaders: [String: String] = [:]) throws -> Rig {
        let id = UUID().uuidString
        let zipURL = URL(string: "https://github.com/Ol775/tether/releases/download/v\(version)/Tether-\(version)-\(id).zip")!
        let sigURL = URL(string: zipURL.absoluteString + ".sig2")!
        StubURLProtocol.stub(zipURL, .init(status: zipStatus, body: zip, headers: zipHeaders))
        let signature = try (signWith ?? key).signature(for: Updater.signedMessage(version: version, zip: zip)).base64EncodedString()
        StubURLProtocol.stub(sigURL, .init(status: 200, body: Data(signature.utf8)))
        let digest = sha ?? SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
        let info = UpdateInfo(version: version, notes: "n", zipURL: zipURL, sha256: digest, sigURL: signed ? sigURL : nil, pageURL: nil)
        let work = try scratch()
        return Rig(installer: UpdateInstaller(workDir: work, session: StubURLProtocol.session, publicKey: pub, maxBytes: maxBytes), info: info, work: work)
    }

    func leftovers(_ work: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: work.path)) ?? []).filter { $0.hasPrefix("update-") } }

    @Test func installsNothingUntilEveryCheckPasses() async throws {
        let r = try rig(zip: try await makeZip())
        let app = try await r.installer.prepare(r.info) { _ in }
        #expect(app.lastPathComponent == "Tether.app" && FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path))
    }

    @Test func refusesAReleaseWithoutASignatureAsset() async throws {
        let r = try rig(zip: try await makeZip(), signed: false)
        await #expect(throws: UpdateError.notSigned) { try await r.installer.prepare(r.info) { _ in } }
        #expect(leftovers(r.work).isEmpty)
    }

    @Test func discardsADownloadSignedByAnotherKey() async throws {
        let r = try rig(zip: try await makeZip(), signWith: Curve25519.Signing.PrivateKey())
        await #expect(throws: UpdateError.badSignature) { try await r.installer.prepare(r.info) { _ in } }
        #expect(leftovers(r.work).isEmpty)
    }

    @Test func discardsADownloadThatDoesNotMatchItsChecksum() async throws {
        let r = try rig(zip: try await makeZip(), sha: String(repeating: "0", count: 64))
        await #expect(throws: UpdateError.badChecksum) { try await r.installer.prepare(r.info) { _ in } }
        #expect(leftovers(r.work).isEmpty)
    }

    @Test func refusesAnAppThatIsNotTether() async throws {
        let r = try rig(zip: try await makeZip(bundleID: "com.example.other"))
        await #expect(throws: UpdateError.notTether) { try await r.installer.prepare(r.info) { _ in } }
        #expect(leftovers(r.work).isEmpty)
    }

    @Test func refusesAnAppWhoseVersionDiffersFromTheRelease() async throws {
        let r = try rig(zip: try await makeZip(version: "0.3.0"), version: "0.2.0")
        await #expect(throws: UpdateError.wrongVersion) { try await r.installer.prepare(r.info) { _ in } }
    }

    @Test func refusesAnAppWithoutAValidCodeSignature() async throws {
        let r = try rig(zip: try await makeZip(codesign: false))
        await #expect(throws: UpdateError.badCodeSignature) { try await r.installer.prepare(r.info) { _ in } }
    }

    @Test func refusesAnOversizeDownload() async throws {
        let r = try rig(zip: try await makeZip(), maxBytes: 10)
        await #expect(throws: UpdateError.tooLarge) { try await r.installer.prepare(r.info) { _ in } }
        #expect(leftovers(r.work).isEmpty)
    }

    @Test func refusesARedirectOffGitHub() async throws {
        // The off-GitHub target serves a perfectly valid, correctly signed zip, so only the redirect guard can stop it.
        let zip = try await makeZip()
        let r = try rig(zip: zip, zipStatus: 302, zipHeaders: ["Location": "https://evil.example/Tether.zip"])
        StubURLProtocol.stub(URL(string: "https://evil.example/Tether.zip")!, .init(status: 200, body: zip))
        await #expect(throws: UpdateError.downloadFailed) { try await r.installer.prepare(r.info) { _ in } }
    }

    @Test func refusesAnAssetOutsideThisReposReleases() async throws {
        let r = try rig(zip: try await makeZip())
        let bad = UpdateInfo(version: "0.2.0", notes: "", zipURL: URL(string: "https://evil.example/Tether.zip")!, sha256: r.info.sha256, sigURL: r.info.sigURL, pageURL: nil)
        await #expect(throws: UpdateError.noDownload) { try await r.installer.prepare(bad) { _ in } }
    }

    // MARK: - applying

    func exitedPID() async throws -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/true"); try p.run(); p.waitUntilExit(); return p.processIdentifier
    }

    @Test func swapsTheNewAppInAndKeepsTheOldOneAsABackup() async throws {
        let r = try rig(zip: try await makeZip(marker: "new"))
        let app = try await r.installer.prepare(r.info) { _ in }
        let dest = try scratch().appendingPathComponent("Tether.app")
        try FileManager.default.createDirectory(at: dest.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try "old".write(to: dest.appendingPathComponent("Contents/marker.txt"), atomically: true, encoding: .utf8)
        try r.installer.apply(app, to: dest, relaunch: false, waitingForPID: try await exitedPID())
        let installed = dest.appendingPathComponent("Contents/marker.txt")
        for _ in 0..<100 where (try? String(contentsOf: installed, encoding: .utf8)) != "new" { try await Task.sleep(for: .milliseconds(50)) }
        #expect(try String(contentsOf: installed, encoding: .utf8) == "new")
        let backup = r.work.appendingPathComponent("previous/Tether.app/Contents/marker.txt")
        #expect(try String(contentsOf: backup, encoding: .utf8) == "old")
    }

    @Test func refusesToApplyAnAppFromOutsideItsWorkFolder() async throws {
        let r = try rig(zip: try await makeZip())
        let stranger = try scratch().appendingPathComponent("Tether.app")
        try FileManager.default.createDirectory(at: stranger, withIntermediateDirectories: true)
        #expect(throws: UpdateError.failedFinalCheck) { try r.installer.apply(stranger, to: try scratch().appendingPathComponent("Tether.app"), relaunch: false, waitingForPID: 1) }
    }

    @Test func aTranslocatedOrReadOnlyCopyCannotSelfUpdate() throws {
        #expect(!UpdateInstaller.canReplace(URL(fileURLWithPath: "/private/var/folders/xx/AppTranslocation/ABC/d/Tether.app")))
        #expect(!UpdateInstaller.canReplace(URL(fileURLWithPath: "/Applications/Tether.txt")))
        let writable = try scratch().appendingPathComponent("Tether.app")
        #expect(UpdateInstaller.canReplace(writable))
    }
}
