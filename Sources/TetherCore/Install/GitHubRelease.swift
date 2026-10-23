import Foundation

public struct ReleaseAsset: Equatable, Sendable {
    public let name: String
    public let size: Int
    public let url: URL
    /// "sha256:<hex>" as reported by GitHub, when present.
    public let digest: String?
}

public struct Release: Sendable {
    public let tag: String
    public let prerelease: Bool
    public let assets: [ReleaseAsset]
}

public enum AssetChoice: Equatable, Sendable {
    case one(ReleaseAsset)
    case ambiguous([ReleaseAsset])
    case none
}

public enum GitHubError: Error, Equatable, Sendable {
    case badRepo, notFound, noCompatibleAPK, truncatedDownload, checksumMismatch, insecureURL
    case rateLimited(resetsAt: Date?)
    case badResponse(Int)

    public var advice: String {
        switch self {
        case .badRepo: "Enter a GitHub repository as owner/name or a github.com link."
        case .notFound: "No published release was found for that repository."
        case .noCompatibleAPK: "The latest release has no APK that fits this device."
        case .truncatedDownload: "The download was incomplete. Try again."
        case .checksumMismatch: "The downloaded file doesn't match GitHub's checksum, so it was not installed."
        case .insecureURL: "Only https downloads are allowed."
        case .rateLimited(let reset):
            "GitHub's rate limit for anonymous requests is used up" + (reset.map { "; try again after \($0.formatted(date: .omitted, time: .shortened))." } ?? ".")
        case .badResponse(let code): "GitHub answered with an unexpected status (\(code))."
        }
    }
}

public enum GitHubRelease {
    public static func parseRepo(_ input: String) -> (owner: String, repo: String)? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var allowExtraSegments = false
        if s.contains("://") {
            guard let url = URL(string: s), url.scheme == "https", ["github.com", "www.github.com"].contains(url.host?.lowercased() ?? "") else { return nil }
            s = url.path
            allowExtraSegments = true
        } else if s.lowercased().hasPrefix("github.com/") {
            s = String(s.dropFirst("github.com/".count))
        }
        let parts = s.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 2 || (allowExtraSegments && parts.count > 2) else { return nil }
        var repo = parts[1]
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        guard validOwner(parts[0]), validRepo(repo) else { return nil }
        return (parts[0], repo)
    }

    public static func latest(owner: String, repo: String, session: URLSession = .shared) async throws -> Release {
        guard validOwner(owner), validRepo(repo), let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else { throw GitHubError.badRepo }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Tether", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        switch http?.statusCode ?? 0 {
        case 200: break
        case 404: throw GitHubError.notFound
        case 403, 429 where http?.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0":
            throw GitHubError.rateLimited(resetsAt: http?.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:)))
        case let code: throw GitHubError.badResponse(code)
        }
        let dto = try JSONDecoder().decode(DTO.self, from: data)
        return Release(tag: dto.tag_name, prerelease: dto.prerelease, assets: dto.assets.map {
            ReleaseAsset(name: $0.name, size: $0.size, url: $0.browser_download_url, digest: $0.digest)
        })
    }

    /// Prefers an APK built for the device's ABI (in the device's own preference order), then an untagged/universal one.
    public static func pick(_ assets: [ReleaseAsset], abis: [String]) -> AssetChoice {
        let apks = assets.filter { $0.name.lowercased().hasSuffix(".apk") }
        func choice(_ list: [ReleaseAsset]) -> AssetChoice? {
            list.isEmpty ? nil : list.count == 1 ? .one(list[0]) : .ambiguous(list)
        }
        for abi in abis {
            if let match = choice(apks.filter { abiTags($0.name).contains(abi) }) { return match }
        }
        return choice(apks.filter { abiTags($0.name).isEmpty }) ?? .none
    }

    // MARK: - internals

    private struct DTO: Decodable {
        struct Asset: Decodable { let name: String; let size: Int; let browser_download_url: URL; let digest: String? }
        let tag_name: String
        let prerelease: Bool
        let assets: [Asset]
    }

    private static let abiAliases: [(String, [String])] = [
        ("arm64-v8a", ["arm64-v8a", "arm64", "aarch64"]),
        ("armeabi-v7a", ["armeabi-v7a", "armv7a", "armv7", "arm32"]),
        ("x86_64", ["x86_64", "x64"]),
        ("x86", ["x86"]),
    ]

    private static func abiTags(_ name: String) -> Set<String> {
        var rest = name.lowercased()
        var tags = Set<String>()
        for (abi, aliases) in abiAliases {
            for alias in aliases where rest.contains(alias) {
                tags.insert(abi)
                rest = rest.replacingOccurrences(of: alias, with: " ")   // so x86 doesn't match inside x86_64
            }
        }
        return tags
    }

    private static func validOwner(_ s: String) -> Bool {
        (1...39).contains(s.count) && !s.hasPrefix("-") && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    private static func validRepo(_ s: String) -> Bool {
        (1...100).contains(s.count) && s != "." && s != ".." && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }
}
