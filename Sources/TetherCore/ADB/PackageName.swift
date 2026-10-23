/// A validated Android package name. adb joins shell args into one remote command string,
/// so this is the only way a package name may reach a command.
public struct PackageName: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let value: String

    public init?(_ raw: String) {
        let segments = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2, segments.allSatisfy(Self.isSegment) else { return nil }
        value = raw
    }

    private static func isSegment(_ s: Substring) -> Bool {
        guard let first = s.unicodeScalars.first, first.isASCII, first.properties.isAlphabetic else { return false }
        return s.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0) || $0 == "_") }
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let name = PackageName(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "invalid package name"))
        }
        self = name
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }

    public static func < (a: PackageName, b: PackageName) -> Bool { a.value < b.value }
    public var description: String { value }
}

public enum PackageState: String, Codable, Sendable {
    case enabled, disabled, removedForUser
}

public struct PackageSnapshot: Codable, Hashable, Sendable {
    public let name: PackageName
    public let state: PackageState

    public init(name: PackageName, state: PackageState) {
        self.name = name
        self.state = state
    }
}
