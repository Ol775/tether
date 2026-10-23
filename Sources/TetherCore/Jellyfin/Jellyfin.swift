import CryptoKit
import Foundation

public enum JellyfinError: LocalizedError, Sendable {
    case noRelease, untrustedAsset, invalidVersion, invalidCommit, missingTools, buildFailed(String), notInstalled, noSavedPackage
    public var errorDescription: String? {
        switch self {
        case .noRelease: "The official Jellyfin release has no compatible stable APK."
        case .untrustedAsset: "The Jellyfin download is not an official release with a SHA-256 checksum."
        case .invalidVersion: "Enter a stable Jellyfin Web version such as 10.10.7, matching your Jellyfin server."
        case .invalidCommit: "GitHub didn't return a valid Jellyfin Tizen source revision. Check for updates and retry."
        case .missingTools: "Building Jellyfin for Samsung needs Git, Node.js 20 or later, npm, Tizen Studio and a Samsung TV signing profile."
        case .buildFailed(let detail): "Jellyfin build failed: \(detail)"
        case .notInstalled: "The device did not confirm that Jellyfin is installed."
        case .noSavedPackage: "No saved Jellyfin package exists for this TV. Build and install it first."
        }
    }
}

public struct JellyfinBuild: Codable, Equatable, Sendable {
    public let webVersion: String
    public let tizenCommit: String
    public let profile: String
    public let package: URL
}

public enum Jellyfin {
    public static let androidID = PackageName("org.jellyfin.androidtv")!
    public static let tizenID = TizenAppID("AprZAARz4r.Jellyfin")!

    public static func stableVersion(_ raw: String) -> String? {
        let version = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        guard version.firstMatch(of: #/^\d+\.\d+\.\d+$/#) != nil else { return nil }
        return version
    }

    public static func androidAsset(_ release: Release, abis: [String]) throws -> ReleaseAsset {
        guard !release.prerelease else { throw JellyfinError.noRelease }
        let assets = release.assets.filter {
            let name = $0.name.lowercased()
            return name.hasSuffix(".apk") && !name.contains("debug") && !name.contains("unsigned")
        }
        let preferred = assets.filter { $0.name.lowercased().hasSuffix("-release.apk") }
        guard case .one(let asset) = GitHubRelease.pick(preferred.isEmpty ? assets : preferred, abis: abis) else {
            throw JellyfinError.noRelease
        }
        guard asset.url.scheme == "https", asset.url.host == "github.com",
              asset.url.path.hasPrefix("/jellyfin/jellyfin-androidtv/releases/download/"),
              let digest = asset.digest, digest.firstMatch(of: #/^sha256:[a-fA-F0-9]{64}$/#) != nil,
              (1...268_435_456).contains(asset.size) else { throw JellyfinError.untrustedAsset }
        return asset
    }

    public static func installedAndroidVersion(_ output: String) -> String? {
        output.firstMatch(of: #/versionName=([^\s]+)/#).map { String($0.1) }
    }

    public static func tizenRevision(session: URLSession = .shared) async throws -> String {
        let url = URL(string: "https://api.github.com/repos/jellyfin/jellyfin-tizen/commits/master")!
        var request = URLRequest(url: url)
        request.setValue("Tether", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw JellyfinError.invalidCommit }
        struct Commit: Decodable { let sha: String }
        let sha = try JSONDecoder().decode(Commit.self, from: data).sha
        guard validCommit(sha) else { throw JellyfinError.invalidCommit }
        return sha
    }

    static func validCommit(_ sha: String) -> Bool { sha.firstMatch(of: #/^[a-fA-F0-9]{40}$/#) != nil }

    public static func cacheFolder(root: URL, deviceID: String) -> URL {
        let key = SHA256.hash(data: Data(deviceID.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("Jellyfin").appendingPathComponent(key, isDirectory: true)
    }

    public static func savedBuild(in folder: URL) -> JellyfinBuild? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("installed.json")),
              let build = try? JSONDecoder().decode(JellyfinBuild.self, from: data),
              build.package.isFileURL,
              build.package.standardizedFileURL.deletingLastPathComponent() == folder.standardizedFileURL,
              FileManager.default.fileExists(atPath: build.package.path) else { return nil }
        return build
    }

    public static func save(_ build: JellyfinBuild, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(build).write(to: folder.appendingPathComponent("installed.json"), options: .atomic)
    }
}
