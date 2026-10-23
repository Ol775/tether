public enum Platform: String, Codable, Sendable {
    case android, fireOS
}

public struct DeviceProfile: Codable, Equatable, Sendable, Identifiable {
    public let serial: String
    public let vendor: String          // lowercased ro.product.manufacturer
    public let model: String
    public let androidVersion: String
    public let sdk: Int
    public let abis: [String]
    public let platform: Platform

    public var id: String { serial }

    public init(serial: String, vendor: String, model: String, androidVersion: String, sdk: Int, abis: [String], platform: Platform) {
        self.serial = serial
        self.vendor = vendor
        self.model = model
        self.androidVersion = androidVersion
        self.sdk = sdk
        self.abis = abis
        self.platform = platform
    }
}
