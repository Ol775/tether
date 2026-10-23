import Foundation

/// A validated Tizen application id. `sdb` and the `tizen` CLI take it as an argument, so this is the only
/// way an app id may reach a command.
public struct TizenAppID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let value: String

    public init?(_ raw: String) {
        // No leading "." or "-": ids become folder names (".." would escape the store) and sdb arguments (options).
        guard (1...128).contains(raw.count), !raw.hasPrefix("."), !raw.hasPrefix("-"),
              raw.unicodeScalars.allSatisfy({ $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0) || "._-".unicodeScalars.contains($0)) })
        else { return nil }
        value = raw
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let id = TizenAppID(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "invalid Tizen app id"))
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }

    public static func < (a: TizenAppID, b: TizenAppID) -> Bool { a.value < b.value }
    public var description: String { value }
}

public struct TizenApp: Codable, Hashable, Sendable, Identifiable {
    public let id: TizenAppID
    public let name: String
    public let version: String?

    public init(id: TizenAppID, name: String, version: String? = nil) {
        self.id = id
        self.name = name
        self.version = version
    }
}

public struct TizenDevice: Codable, Equatable, Sendable, Identifiable {
    /// Address sdb talks to (IP:port); changes with DHCP.
    public let serial: String
    /// Hardware identity that survives an address change: the TV's DUID, else the address.
    public let deviceID: String
    public let model: String
    public let modelYear: Int?
    public let tizenVersion: String
    public let shellEnabled: Bool
    public let rootAvailable: Bool

    public var id: String { serial }

    public init(serial: String, deviceID: String? = nil, model: String, modelYear: Int?, tizenVersion: String, shellEnabled: Bool, rootAvailable: Bool) {
        self.serial = serial
        self.deviceID = deviceID ?? serial
        self.model = model
        self.modelYear = modelYear
        self.tizenVersion = tizenVersion
        self.shellEnabled = shellEnabled
        self.rootAvailable = rootAvailable
    }
}
