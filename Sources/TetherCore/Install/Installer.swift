import CryptoKit
import Foundation

public actor Installer {
    private let adb: ADBRunner
    private let session: URLSession

    public init(adb: ADBRunner, session: URLSession = .shared) {
        self.adb = adb
        self.session = session
    }

    public func install(apk: URL, on device: DeviceProfile) async throws {
        let out = try await adb.run(["install", "-r", apk.path], serial: device.serial)
        guard out.contains("Success") else { throw ADBError.classify(code: 1, output: out) }
    }

    /// `chooser` is asked only when several assets fit; returning nil cancels.
    @discardableResult
    public func installLatest(of repoInput: String, on device: DeviceProfile,
                              chooser: @Sendable ([ReleaseAsset]) async -> ReleaseAsset?) async throws -> ReleaseAsset {
        guard let (owner, repo) = GitHubRelease.parseRepo(repoInput) else { throw GitHubError.badRepo }
        let release = try await GitHubRelease.latest(owner: owner, repo: repo, session: session)
        let asset: ReleaseAsset
        switch GitHubRelease.pick(release.assets, abis: device.abis) {
        case .one(let a): asset = a
        case .none: throw GitHubError.noCompatibleAPK
        case .ambiguous(let options):
            guard let picked = await chooser(options) else { throw CancellationError() }
            asset = picked
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tether-dl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try await download(asset, into: dir)
        try await install(apk: file, on: device)
        return asset
    }

    private func download(_ asset: ReleaseAsset, into dir: URL) async throws -> URL {
        guard asset.url.scheme == "https" else { throw GitHubError.insecureURL }
        let (temp, response) = try await session.download(from: asset.url)
        defer { try? FileManager.default.removeItem(at: temp) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw GitHubError.badResponse(status) }
        let size = (try FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? Int) ?? -1
        guard size == asset.size else { throw GitHubError.truncatedDownload }
        if let digest = asset.digest, digest.hasPrefix("sha256:") {
            let actual = SHA256.hash(data: try Data(contentsOf: temp, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
            guard actual == digest.dropFirst(7).lowercased() else { throw GitHubError.checksumMismatch }
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = (asset.name as NSString).lastPathComponent
        let dest = dir.appendingPathComponent(name.isEmpty ? "app.apk" : name)
        try FileManager.default.moveItem(at: temp, to: dest)
        return dest
    }
}
