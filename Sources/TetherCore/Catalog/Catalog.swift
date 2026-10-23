import Foundation

public enum RiskTier: String, Codable, CaseIterable, Comparable, Sendable {
    case safe, recommended, advanced, expert

    public static func < (a: RiskTier, b: RiskTier) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

public struct CatalogEntry: Codable, Identifiable, Equatable, Sendable {
    public let package: PackageName
    /// Lowercase manufacturers; "*" matches any.
    public let vendors: [String]
    public let platforms: [Platform]?
    public let tier: RiskTier
    public let title: String
    public let description: String
    public let breaks: String?
    /// Where this entry's claim came from (provenance, shown in docs/inspector).
    public let source: String

    public var id: String { "\(package.value)|\(vendors.joined(separator: ","))" }
}

public enum CatalogError: Error, Equatable, Sendable {
    case duplicate(String)
    case emptyField(String, String)
    case missingBreaks(String)
    case unsupportedVersion(Int)
    case insecureURL
}

public struct Catalog: Sendable {
    public let entries: [CatalogEntry]

    private struct File: Decodable { let version: Int; let entries: [CatalogEntry] }

    public static func decode(_ data: Data) throws -> Catalog {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.version == 1 else { throw CatalogError.unsupportedVersion(file.version) }
        var seen = Set<String>()
        for e in file.entries {
            let name = e.package.value
            for (field, text) in [("title", e.title), ("description", e.description), ("source", e.source)]
            where text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw CatalogError.emptyField(name, field)
            }
            if e.tier >= .advanced, (e.breaks ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                throw CatalogError.missingBreaks(name)
            }
            for vendor in e.vendors where !seen.insert("\(name)|\(vendor)").inserted {
                throw CatalogError.duplicate(name)
            }
        }
        return Catalog(entries: file.entries)
    }

    /// Entries that apply to this device and whose package is actually installed.
    public func entries(for device: DeviceProfile, installed: Set<PackageName>) -> [CatalogEntry] {
        entries.filter { e in
            installed.contains(e.package)
                && (e.vendors.contains("*") || e.vendors.contains(device.vendor))
                && (e.platforms?.contains(device.platform) ?? true)
        }
    }
}
