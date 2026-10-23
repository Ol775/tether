import CryptoKit
import Foundation

public struct UpdateInfo: Sendable, Equatable {
    public let version: String
    public let notes: String
    public var zipURL: URL?     // the release's zip, when it comes from this repo's GitHub releases
    public var sha256: String?  // its expected checksum
    public var sigURL: URL?     // detached Ed25519 signature made offline with the release key
    public var pageURL: URL?    // the release page, for copies that can't replace themselves

    public init(version: String, notes: String, zipURL: URL? = nil, sha256: String? = nil, sigURL: URL? = nil, pageURL: URL? = nil) {
        self.version = version; self.notes = notes; self.zipURL = zipURL; self.sha256 = sha256; self.sigURL = sigURL; self.pageURL = pageURL
    }
}

public enum UpdateError: Error, Equatable, Sendable {
    case checkFailed(status: Int)
    case noDownload, notSigned, downloadFailed, tooLarge
    case badSignature, badChecksum, changedAfterCheck
    case unzipFailed, notTether, wrongVersion, badCodeSignature, failedFinalCheck, cannotStartInstaller

    public var advice: String {
        switch self {
        case .checkFailed: "Couldn't reach GitHub. Check your internet connection and try again."
        case .noDownload: "This release has no download Tether trusts. Get it from the releases page instead."
        case .notSigned: "This release isn't signed, so it won't be installed automatically. Download it from the releases page instead."
        case .downloadFailed: "Couldn't download the update."
        case .tooLarge: "The download was far bigger than a Tether release, so it was discarded."
        case .badSignature: "The download's signature didn't check out, so it was discarded."
        case .badChecksum: "The download didn't match its checksum, so it was discarded."
        case .changedAfterCheck: "The download changed after it was checked, so it was discarded."
        case .unzipFailed: "Couldn't open the downloaded file."
        case .notTether: "The download isn't Tether."
        case .wrongVersion: "The download held a different version than the release says."
        case .badCodeSignature: "The app's code signature didn't check out."
        case .failedFinalCheck: "The update didn't pass its final check, so it wasn't installed."
        case .cannotStartInstaller: "Couldn't start the installer."
        }
    }
}

/// Finds a newer release on GitHub. Mirrors the trust model of Claude Usage: GitHub carries the files, but only a
/// signature made offline with the release key makes an update installable (see `UpdateInstaller`).
public enum Updater {
    public static let repo = "Ol775/tether"

    /// Ed25519 public key every release zip must be signed with. The private key lives only on the maintainer's Mac,
    /// so a hijacked GitHub account or release can't push an update that installs.
    public static let publicKey = "WvP+khXEstqAPVjcfdAgBAXMY9GlmYM4602Q0vozwvg="

    private static func parts(_ v: String) -> [Int] { v.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 } }

    /// True when `a` is newer than `b` (both "major.minor.patch").
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// "1.2.3": digits and dots only, so a hostile tag can't smuggle odd characters into file names or messages.
    public static func isPlainVersion(_ v: String) -> Bool {
        v.range(of: #"^\d{1,4}\.\d{1,4}\.\d{1,4}$"#, options: .regularExpression) != nil
    }

    /// What the release key signs: a label, the version and the zip bytes, so a validly signed older zip can't pass for a newer release.
    public static func signedMessage(version: String, zip: Data) -> Data { Data("tether-update\nv\(version)\n".utf8) + zip }

    /// Only these hosts may serve a release download (GitHub and its asset CDN), also after redirects.
    public static func isAllowedRedirectHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased() else { return false }
        return h == "github.com" || h.hasSuffix(".githubusercontent.com")
    }

    /// Release downloads must come from this repo's GitHub releases, with no dot-segments in the path.
    public static func isTrustedAsset(_ u: URL, repo: String = Updater.repo) -> Bool {
        let path = u.path
        return u.scheme == "https" && u.host == "github.com" && path.hasPrefix("/\(repo)/releases/download/")
            && !path.contains("..") && !u.absoluteString.lowercased().contains("%2e")
    }

    public static func verifySignature(_ data: Data, base64Signature: String, publicKey key: String = Updater.publicKey) -> Bool {
        guard let k = Data(base64Encoded: key), let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: k),
              let sig = Data(base64Encoded: base64Signature.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return pub.isValidSignature(sig, for: data)
    }

    /// Reads GitHub's release JSON. Assets that aren't from this repo's releases are dropped; a tag that isn't a plain version yields nil.
    public static func parseRelease(_ data: Data, repo: String = Updater.repo) -> UpdateInfo? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let tag = json["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isPlainVersion(version) else { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        func trusted(_ asset: [String: Any]?) -> URL? {
            (asset?["browser_download_url"] as? String).flatMap(URL.init(string:)).flatMap { isTrustedAsset($0, repo: repo) ? $0 : nil }
        }
        let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
        let zipName = zip?["name"] as? String ?? ""
        let sig = assets.first { $0["name"] as? String == zipName + ".sig2" }
        let sha = (zip?["digest"] as? String).flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil }
        let page = (json["html_url"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" && $0.host == "github.com" && $0.path.hasPrefix("/\(repo)/releases/") ? $0 : nil }
        return UpdateInfo(version: version, notes: (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                          zipURL: trusted(zip), sha256: sha, sigURL: trusted(sig), pageURL: page)
    }

    /// The newest GitHub release (GitHub's "latest", which never is a draft or pre-release); nil when the repo has none.
    public static func latest(session: URLSession = .shared, repo: String = Updater.repo) async throws -> UpdateInfo? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard status == 200, data.count < 1_000_000 else { throw UpdateError.checkFailed(status: status) }
        return parseRelease(data, repo: repo)
    }
}
