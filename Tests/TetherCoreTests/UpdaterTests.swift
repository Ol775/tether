import CryptoKit
import Foundation
import Testing
@testable import TetherCore

struct UpdaterTests {
    // MARK: - pure rules

    @Test(arguments: [("1.2.3", "1.2.2", true), ("1.10.0", "1.9.9", true), ("2.0.0", "1.99.99", true), ("1.2.3", "1.2.3", false), ("1.2.2", "1.2.3", false), ("0.1.0", "0.1", false)])
    func newerVersionsWin(a: String, b: String, newer: Bool) { #expect(Updater.isNewer(a, than: b) == newer) }

    @Test func onlyPlainVersionsAreAccepted() {
        for ok in ["0.1.0", "1.2.3", "10.20.30"] { #expect(Updater.isPlainVersion(ok), "\(ok)") }
        for bad in ["1.2", "v1.2.3", "1.2.3-beta", "1.2.3; rm", "../1.2.3", "", "1.2.3.4", "12345.1.1"] { #expect(!Updater.isPlainVersion(bad), "\(bad)") }
    }

    @Test func onlyThisReposReleaseAssetsAreTrusted() {
        let ok = URL(string: "https://github.com/Ol775/tether/releases/download/v0.1.0/Tether-0.1.0.zip")!
        #expect(Updater.isTrustedAsset(ok))
        for bad in ["http://github.com/Ol775/tether/releases/download/v1/x.zip", "https://github.com/Other/tether/releases/download/v1/x.zip",
                    "https://evil.example/Ol775/tether/releases/download/v1/x.zip", "https://github.com/Ol775/tether/releases/download/../../../evil/x.zip",
                    "https://github.com/Ol775/tether/archive/main.zip", "https://github.com.evil.example/Ol775/tether/releases/download/v1/x.zip"] {
            #expect(!Updater.isTrustedAsset(URL(string: bad)!), "\(bad)")
        }
    }

    @Test func redirectsMayOnlyStayOnGitHub() {
        for ok in ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"] { #expect(Updater.isAllowedRedirectHost(ok)) }
        for bad in ["evil.example", "githubusercontent.com.evil.example", "notgithub.com", ""] { #expect(!Updater.isAllowedRedirectHost(bad)) }
        #expect(!Updater.isAllowedRedirectHost(nil))
    }

    @Test func signatureIsBoundToVersionAndKey() throws {
        let key = Curve25519.Signing.PrivateKey()
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        let zip = Data("zip bytes".utf8)
        let sig = try key.signature(for: Updater.signedMessage(version: "1.0.1", zip: zip)).base64EncodedString()
        #expect(Updater.verifySignature(Updater.signedMessage(version: "1.0.1", zip: zip), base64Signature: sig, publicKey: pub))
        #expect(!Updater.verifySignature(Updater.signedMessage(version: "1.0.2", zip: zip), base64Signature: sig, publicKey: pub))   // older image can't pose as newer
        #expect(!Updater.verifySignature(Updater.signedMessage(version: "1.0.1", zip: zip + [0]), base64Signature: sig, publicKey: pub))
        let other = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        #expect(!Updater.verifySignature(Updater.signedMessage(version: "1.0.1", zip: zip), base64Signature: sig, publicKey: other))
        #expect(!Updater.verifySignature(Data(), base64Signature: "not base64!", publicKey: pub))
    }

    // MARK: - release JSON

    func release(tag: String = "v0.2.0", zip: String = "https://github.com/Ol775/tether/releases/download/v0.2.0/Tether-0.2.0.zip",
                 sig: String = "https://github.com/Ol775/tether/releases/download/v0.2.0/Tether-0.2.0.zip.sig2", digest: String? = "sha256:ABCDEF") -> Data {
        let digestField = digest.map { #","digest":"\#($0)""# } ?? ""
        return Data(#"""
        {"tag_name":"\#(tag)","body":"Fixes things.","html_url":"https://github.com/Ol775/tether/releases/tag/\#(tag)","assets":[
          {"name":"Tether-0.2.0.zip","browser_download_url":"\#(zip)"\#(digestField)},
          {"name":"Tether-0.2.0.zip.sig2","browser_download_url":"\#(sig)"}]}
        """#.utf8)
    }

    @Test func parsesASignedRelease() throws {
        let info = try #require(Updater.parseRelease(release()))
        #expect(info.version == "0.2.0" && info.sha256 == "abcdef" && info.zipURL?.lastPathComponent == "Tether-0.2.0.zip" && info.sigURL?.lastPathComponent == "Tether-0.2.0.zip.sig2")
        #expect(info.notes == "Fixes things.")
    }

    @Test func dropsAssetsFromOtherPlacesAndBadTags() throws {
        let info = try #require(Updater.parseRelease(release(zip: "https://evil.example/Tether-0.2.0.zip", sig: "http://github.com/Ol775/tether/releases/download/v0.2.0/x.sig2")))
        #expect(info.zipURL == nil && info.sigURL == nil)
        #expect(Updater.parseRelease(release(tag: "v1.2")) == nil)
        #expect(Updater.parseRelease(release(tag: "latest")) == nil)
        #expect(Updater.parseRelease(Data("nonsense".utf8)) == nil)
    }

    @Test func latestReadsGitHubsLatestReleaseAndTreatsNoReleaseAsNone() async throws {
        let api = URL(string: "https://api.github.com/repos/Ol775/tether/releases/latest")!
        StubURLProtocol.stub(api, .init(status: 200, body: release()))
        #expect(try await Updater.latest(session: StubURLProtocol.session)?.version == "0.2.0")
        StubURLProtocol.stub(api, .init(status: 404, body: Data()))
        #expect(try await Updater.latest(session: StubURLProtocol.session) == nil)
        StubURLProtocol.stub(api, .init(status: 500, body: Data()))
        await #expect(throws: UpdateError.checkFailed(status: 500)) { try await Updater.latest(session: StubURLProtocol.session) }
    }
}
