import Foundation

public enum TizenChange: Codable, Hashable, Sendable {
    case uninstall(TizenAppID)
    /// A signed `.wgt` or `.tpk` on the Mac.
    case install(wgt: URL)

    /// Throws before anything runs. Arguments are passed as an array, never a shell string, but a path
    /// still has to be an absolute existing package so it can't be read as an option.
    func validate() throws {
        guard case .install(let url) = self else { return }
        let ok = url.isFileURL && url.path.hasPrefix("/") && ["wgt", "tpk"].contains(url.pathExtension.lowercased())
            && FileManager.default.fileExists(atPath: url.path)
        guard ok else { throw TizenError.unsafeValue }
    }
}

public struct TizenRestorePoint: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let reason: String
    public let device: TizenDevice
    public let apps: [TizenApp]
    /// The changes this restore point was taken for; a revert undoes exactly these.
    public let changes: [TizenChange]
}
