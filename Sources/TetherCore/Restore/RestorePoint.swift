import Foundation

public struct RestorePoint: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let reason: String
    public let profile: DeviceProfile
    public let packages: [PackageSnapshot]
    /// namespace (global | secure | system) → key → value
    public let settings: [String: [String: String]]
    /// package → paths relative to the restore point folder
    public let apks: [String: [String]]
    /// nil = no user override
    public let density: Int?
    /// Default launcher component, when the device reports one.
    public let home: String?
}

public enum RestoreError: Error, Equatable, Sendable {
    case unverified(String)
    case notFound(UUID)
}
