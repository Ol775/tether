import Foundation

public struct TizenCatalogEntry: Codable, Identifiable, Equatable, Sendable {
    public let app: TizenAppID
    public let tier: RiskTier
    public let title: String
    public let description: String
    public let breaks: String?
    /// First model year known to let `sdb` remove this app; nil = not known to be removable.
    public let removableFromYear: Int?
    /// Where this entry's claim came from.
    public let source: String

    public var id: String { app.value }
}

public struct TizenCatalog: Sendable {
    public let entries: [TizenCatalogEntry]

    private struct File: Decodable { let version: Int; let entries: [TizenCatalogEntry] }

    public static func decode(_ data: Data) throws -> TizenCatalog {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.version == 1 else { throw CatalogError.unsupportedVersion(file.version) }
        var seen = Set<String>()
        for e in file.entries {
            let name = e.app.value
            for (field, text) in [("title", e.title), ("description", e.description), ("source", e.source)]
            where text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw CatalogError.emptyField(name, field)
            }
            if e.tier >= .advanced, (e.breaks ?? "").trimmingCharacters(in: .whitespaces).isEmpty { throw CatalogError.missingBreaks(name) }
            guard seen.insert(name).inserted else { throw CatalogError.duplicate(name) }
        }
        return TizenCatalog(entries: file.entries)
    }

    public static func bundled() throws -> TizenCatalog {
        guard let url = Resources.url("tizen-catalog", "json") else { throw CatalogError.emptyField("bundle", "tizen-catalog.json") }
        return try decode(Data(contentsOf: url))
    }

    public func entries(installed: Set<TizenAppID>) -> [TizenCatalogEntry] {
        entries.filter { installed.contains($0.app) }
    }

    /// A hint only: the real answer comes from trying the removal and re-reading the TV.
    public func likelyLocked(_ entry: TizenCatalogEntry, on device: TizenDevice) -> Bool {
        guard let from = entry.removableFromYear else { return true }
        return (device.modelYear ?? 0) < from
    }
}
