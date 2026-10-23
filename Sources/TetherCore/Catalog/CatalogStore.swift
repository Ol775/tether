import Foundation

/// Bundled catalog, optionally superseded by a validated refresh stored in `overrideDir`.
public struct CatalogStore: Sendable {
    private let overrideDir: URL
    private var overrideFile: URL { overrideDir.appendingPathComponent("catalog.json") }

    public init(overrideDir: URL) { self.overrideDir = overrideDir }

    public func load() throws -> Catalog {
        if let data = try? Data(contentsOf: overrideFile), let catalog = try? Catalog.decode(data) { return catalog }
        guard let url = Resources.url("catalog", "json") else { throw CatalogError.emptyField("bundle", "catalog.json") }
        return try Catalog.decode(Data(contentsOf: url))
    }

    /// Returns false when the server has no catalog (404). Invalid data throws and changes nothing.
    public func refresh(from url: URL, session: URLSession = .shared) async throws -> Bool {
        guard url.scheme == "https" else { throw CatalogError.insecureURL }
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return false }
        guard status == 200 else { throw ADBError.commandFailed(code: Int32(status), stderr: "catalog refresh failed (HTTP \(status))") }
        _ = try Catalog.decode(data)
        try FileManager.default.createDirectory(at: overrideDir, withIntermediateDirectories: true)
        try data.write(to: overrideFile, options: .atomic)
        return true
    }
}

enum Resources {
    /// SwiftPM's `Bundle.module` can't find the bundle inside a .app's Resources folder, so look there first.
    static func url(_ name: String, _ ext: String) -> URL? {
        if let bundle = Bundle.main.resourceURL.flatMap({ Bundle(url: $0.appendingPathComponent("Tether_TetherCore.bundle")) }),
           let url = bundle.url(forResource: name, withExtension: ext) {
            return url
        }
        return Bundle.module.url(forResource: name, withExtension: ext)
    }
}
