import CryptoKit
import Foundation
import Testing
@testable import TetherCore

struct InstallerTests {
    let phone = DeviceProfile(serial: "192.168.1.5:5555", vendor: "google", model: "Pixel", androidVersion: "15", sdk: 35, abis: ["arm64-v8a", "armeabi-v7a"], platform: .android)

    func asset(_ name: String, size: Int = 3, digest: String? = nil) -> ReleaseAsset {
        ReleaseAsset(name: name, size: size, url: URL(string: "https://github.com/o/r/releases/download/v1/\(name)")!, digest: digest)
    }

    @Test func parsesRepoURLs() {
        for input in ["https://github.com/o/r", "github.com/o/r", "o/r", "https://github.com/o/r.git", "https://github.com/o/r/", "https://github.com/o/r/releases/tag/v1"] {
            let parsed = GitHubRelease.parseRepo(input)
            #expect(parsed?.owner == "o" && parsed?.repo == "r", "\(input)")
        }
        for bad in ["", "o", "o/r/../x;y", "https://evil.example/o/r", "o r/x", "o/r;rm", "http://github.com/o/r", "-o/r"] {
            #expect(GitHubRelease.parseRepo(bad) == nil, "\(bad)")
        }
    }

    @Test func picksMatchingABI() {
        let choice = GitHubRelease.pick([asset("app-arm64-v8a.apk"), asset("app-armeabi-v7a.apk"), asset("app-x86.apk"), asset("app-x86_64.apk")], abis: phone.abis)
        #expect(choice == .one(asset("app-arm64-v8a.apk")))
    }

    @Test func prefersUniversalWhenNoABIMatch() {
        let choice = GitHubRelease.pick([asset("app-x86.apk"), asset("app-universal.apk")], abis: phone.abis)
        #expect(choice == .one(asset("app-universal.apk")))
    }

    @Test func untaggedSingleAPKIsChosen() {
        #expect(GitHubRelease.pick([asset("app.apk"), asset("notes.txt")], abis: phone.abis) == .one(asset("app.apk")))
    }

    @Test func ambiguousWhenSeveralFit() {
        let choice = GitHubRelease.pick([asset("app-debug.apk"), asset("app-release.apk")], abis: phone.abis)
        #expect(choice == .ambiguous([asset("app-debug.apk"), asset("app-release.apk")]))
    }

    @Test func noneWhenOnlyIncompatibleABIsOrNoAPK() {
        #expect(GitHubRelease.pick([asset("app-x86.apk"), asset("app-x86_64.apk")], abis: phone.abis) == .none)
        #expect(GitHubRelease.pick([asset("source.zip")], abis: phone.abis) == .none)
    }

    @Test func latestParsesRelease() async throws {
        let owner = "o\(Int.random(in: 1000...9999))"
        StubURLProtocol.stub(URL(string: "https://api.github.com/repos/\(owner)/r/releases/latest")!, .init(status: 200, body: Data(fixture("release-multi-abi.json").utf8)))
        let release = try await GitHubRelease.latest(owner: owner, repo: "r", session: StubURLProtocol.session)
        #expect(release.tag == "v1.2.3")
        #expect(release.assets.count == 5)
        #expect(GitHubRelease.pick(release.assets, abis: ["armeabi-v7a"]) == .one(release.assets[1]))
    }

    @Test func releaseWithoutAPKPicksNone() async throws {
        let owner = "n\(Int.random(in: 1000...9999))"
        StubURLProtocol.stub(URL(string: "https://api.github.com/repos/\(owner)/r/releases/latest")!, .init(status: 200, body: Data(fixture("release-no-apk.json").utf8)))
        let release = try await GitHubRelease.latest(owner: owner, repo: "r", session: StubURLProtocol.session)
        #expect(GitHubRelease.pick(release.assets, abis: phone.abis) == .none)
    }

    @Test func rateLimitedThrowsFriendly() async throws {
        let owner = "rl\(Int.random(in: 1000...9999))"
        StubURLProtocol.stub(URL(string: "https://api.github.com/repos/\(owner)/r/releases/latest")!,
                             .init(status: 403, body: Data(), headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1900000000"]))
        do {
            _ = try await GitHubRelease.latest(owner: owner, repo: "r", session: StubURLProtocol.session)
            Issue.record("expected rate limit")
        } catch let error as GitHubError {
            guard case .rateLimited = error else { Issue.record("wrong error \(error)"); return }
            #expect(error.advice.lowercased().contains("rate limit"))
        }
    }

    @Test func plainForbiddenIsNotReportedAsRateLimit() async throws {
        let owner = "fb\(Int.random(in: 1000...9999))"
        StubURLProtocol.stub(URL(string: "https://api.github.com/repos/\(owner)/r/releases/latest")!, .init(status: 403, body: Data()))
        await #expect(throws: GitHubError.badResponse(403)) {
            try await GitHubRelease.latest(owner: owner, repo: "r", session: StubURLProtocol.session)
        }
    }

    @Test func notFoundThrows() async throws {
        await #expect(throws: GitHubError.notFound) {
            try await GitHubRelease.latest(owner: "nobody\(Int.random(in: 1000...9999))", repo: "r", session: StubURLProtocol.session)
        }
    }

    @Test func installUsesSerial() async throws {
        let fake = try FakeADB()
        try await Installer(adb: fake.runner).install(apk: URL(fileURLWithPath: "/tmp/x/app.apk"), on: phone)
        #expect(fake.calls() == ["-P 5038 -s 192.168.1.5:5555 install -r /tmp/x/app.apk"])
    }

    func stubRelease(_ name: String, body: Data, size: Int, digest: String? = nil) -> String {
        let owner = "i\(Int.random(in: 100000...999999))"
        let url = "https://github.com/\(owner)/r/releases/download/v1/\(name)"
        var assetJSON: [String: Any] = ["name": name, "size": size, "browser_download_url": url]
        if let digest { assetJSON["digest"] = digest }
        let release = try! JSONSerialization.data(withJSONObject: ["tag_name": "v1", "draft": false, "prerelease": false, "assets": [assetJSON]])
        StubURLProtocol.stub(URL(string: "https://api.github.com/repos/\(owner)/r/releases/latest")!, .init(status: 200, body: release))
        StubURLProtocol.stub(URL(string: url)!, .init(status: 200, body: body))
        return "\(owner)/r"
    }

    @Test func installLatestDownloadsVerifiesAndInstalls() async throws {
        let body = Data("apk-bytes".utf8)
        let sha = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let repo = stubRelease("app.apk", body: body, size: body.count, digest: "sha256:\(sha)")
        let fake = try FakeADB()
        let installed = try await Installer(adb: fake.runner, session: StubURLProtocol.session).installLatest(of: repo, on: phone) { _ in nil }
        #expect(installed.name == "app.apk")
        #expect(fake.lines("installs.log").count == 1)
    }

    @Test func rejectsTruncatedDownload() async throws {
        let repo = stubRelease("app.apk", body: Data("abc".utf8), size: 10)
        let fake = try FakeADB()
        await #expect(throws: GitHubError.truncatedDownload) {
            try await Installer(adb: fake.runner, session: StubURLProtocol.session).installLatest(of: repo, on: phone) { _ in nil }
        }
        #expect(fake.lines("installs.log").isEmpty)
    }

    @Test func rejectsChecksumMismatch() async throws {
        let repo = stubRelease("app.apk", body: Data("abc".utf8), size: 3, digest: "sha256:" + String(repeating: "0", count: 64))
        let fake = try FakeADB()
        await #expect(throws: GitHubError.checksumMismatch) {
            try await Installer(adb: fake.runner, session: StubURLProtocol.session).installLatest(of: repo, on: phone) { _ in nil }
        }
        #expect(fake.lines("installs.log").isEmpty)
    }

    @Test func ambiguousAssetsGoToTheChooser() async throws {
        let owner = "amb\(Int.random(in: 100000...999999))"
        let release = try JSONSerialization.data(withJSONObject: ["tag_name": "v1", "draft": false, "prerelease": false, "assets": [
            ["name": "a-debug.apk", "size": 3, "browser_download_url": "https://github.com/\(owner)/r/d/a-debug.apk"],
            ["name": "a-release.apk", "size": 3, "browser_download_url": "https://github.com/\(owner)/r/d/a-release.apk"]]])
        StubURLProtocol.stub(URL(string: "https://api.github.com/repos/\(owner)/r/releases/latest")!, .init(status: 200, body: release))
        StubURLProtocol.stub(URL(string: "https://github.com/\(owner)/r/d/a-release.apk")!, .init(status: 200, body: Data("abc".utf8)))
        let fake = try FakeADB()
        let chosen = try await Installer(adb: fake.runner, session: StubURLProtocol.session).installLatest(of: "\(owner)/r", on: phone) { options in
            options.first { $0.name == "a-release.apk" }
        }
        #expect(chosen.name == "a-release.apk")
        await #expect(throws: CancellationError.self) {
            try await Installer(adb: fake.runner, session: StubURLProtocol.session).installLatest(of: "\(owner)/r", on: phone) { _ in nil }
        }
    }
}
