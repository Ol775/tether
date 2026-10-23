import Foundation
import Testing
@testable import TetherCore

struct JellyfinTests {
    func asset(_ name: String, url: String? = nil, digest: String? = "sha256:" + String(repeating: "a", count: 64)) -> ReleaseAsset {
        ReleaseAsset(name: name, size: 10, url: URL(string: url ?? "https://github.com/jellyfin/jellyfin-androidtv/releases/download/v1.2.3/\(name)")!, digest: digest)
    }

    @Test func choosesStableReleaseAPKInsteadOfDebugBuild() throws {
        let debug = asset("jellyfin-androidtv-debug.apk")
        let release = asset("jellyfin-androidtv-release.apk")
        let result = try Jellyfin.androidAsset(Release(tag: "v1.2.3", prerelease: false, assets: [debug, release]), abis: ["arm64-v8a"])
        #expect(result == release)
    }

    @Test func rejectsUntrustedOrUncheckedAPKs() {
        for candidate in [asset("app.apk", url: "https://elsewhere.example/app.apk"), asset("app.apk", digest: nil), asset("app.apk", digest: "sha256:nope")] {
            #expect(throws: (any Error).self) { try Jellyfin.androidAsset(Release(tag: "v1.2.3", prerelease: false, assets: [candidate]), abis: []) }
        }
    }

    @Test func neverInstallsDebugOrPrerelease() {
        #expect(throws: (any Error).self) { try Jellyfin.androidAsset(Release(tag: "v1.2.3", prerelease: false, assets: [asset("app-debug.apk")]), abis: []) }
        #expect(throws: (any Error).self) { try Jellyfin.androidAsset(Release(tag: "v1.2.3", prerelease: true, assets: [asset("app-release.apk")]), abis: []) }
    }

    @Test func validatesSourceBuildInputs() throws {
        let root = URL(fileURLWithPath: "/tmp/build with spaces")
        let commit = String(repeating: "a", count: 40)
        for version in ["master", "1.2.3;rm", "../x", "--help"] {
            #expect(throws: (any Error).self) { try JellyfinTizenBuilder.steps(root: root, version: version, commit: commit, profile: "TV") }
        }
        #expect(throws: (any Error).self) { try JellyfinTizenBuilder.steps(root: root, version: "1.2.3", commit: "master", profile: "TV") }
        let steps = try JellyfinTizenBuilder.steps(root: root, version: "v1.2.3", commit: commit, profile: "My TV")
        #expect(steps.first?.arguments.contains("https://github.com/jellyfin/jellyfin-web.git") == true)
        #expect(steps.contains { $0.arguments == ["fetch", "--depth", "1", "origin", commit] })
        #expect(steps.last?.arguments.contains("My TV") == true)
        #expect(steps.contains { $0.environment["JELLYFIN_WEB_DIR"] == "/tmp/build with spaces/jellyfin-web/dist" })
        #expect(!steps.contains { $0.arguments.contains("uninstall") })
    }

    @Test func parsesInstalledVersion() {
        #expect(Jellyfin.installedAndroidVersion("Package [org.jellyfin.androidtv]\n    versionName=0.19.10\n") == "0.19.10")
        #expect(Jellyfin.installedAndroidVersion("not installed") == nil)
    }

    @Test func savedBuildIsDeviceScopedAndRequiresPackage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = Jellyfin.cacheFolder(root: root, deviceID: "tv:1/../../outside")
        #expect(folder.deletingLastPathComponent().lastPathComponent == "Jellyfin")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let package = folder.appendingPathComponent("Jellyfin.wgt")
        try Data("signed package".utf8).write(to: package)
        let build = JellyfinBuild(webVersion: "1.2.3", tizenCommit: String(repeating: "a", count: 40), profile: "TV", package: package)
        try Jellyfin.save(build, in: folder)
        #expect(Jellyfin.savedBuild(in: folder) == build)
        #expect(Jellyfin.savedBuild(in: Jellyfin.cacheFolder(root: root, deviceID: "another TV")) == nil)
        try FileManager.default.removeItem(at: package)
        #expect(Jellyfin.savedBuild(in: folder) == nil)
    }

    @Test func sdbExitZeroInstallErrorsAreFailures() {
        for output in ["install failed: invalid certificate", "error: signature mismatch", "", "install started"] {
            #expect(throws: (any Error).self) { try TizenChangeEngine.checkInstallOutput(output) }
        }
        #expect(throws: Never.self) { try TizenChangeEngine.checkInstallOutput("install completed\nSuccess") }
    }

    @Test func packageConfigMustDeclareTheOfficialAppID() {
        #expect(JellyfinTizenBuilder.declaresJellyfin("<widget><tizen:application id=\"AprZAARz4r.Jellyfin\" package=\"AprZAARz4r\"/></widget>"))
        #expect(!JellyfinTizenBuilder.declaresJellyfin("<widget><tizen:application id=\"evil.App\"/></widget>"))
        #expect(!JellyfinTizenBuilder.declaresJellyfin(""))
    }
}
