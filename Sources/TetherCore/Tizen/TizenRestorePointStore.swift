import Foundation

/// One folder per snapshot: `<root>/<id>/restore.json`. Signed packages Tether installed are kept in
/// `<root>/wgts/<appID>/` so a later uninstall can be undone.
public actor TizenRestorePointStore {
    private let root: URL

    public init(root: URL) { self.root = root }

    public func create(device: TizenDevice, reason: String, apps: [TizenApp], changes: [TizenChange]) throws -> TizenRestorePoint {
        let id = UUID()
        let folder = root.appendingPathComponent(id.uuidString)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let now = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 * 1000).rounded() / 1000)
            let rp = TizenRestorePoint(id: id, createdAt: now, reason: reason, device: device, apps: apps, changes: changes)
            try Self.encoder.encode(rp).write(to: folder.appendingPathComponent("restore.json"), options: .atomic)
            guard try read(folder) == rp else { throw RestoreError.unverified("restore.json did not read back identically") }
            return rp
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    public func list() -> [TizenRestorePoint] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { try? read($0) }.sorted { $0.createdAt > $1.createdAt }
    }

    public func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: root.appendingPathComponent(id.uuidString))
    }

    public func saveWGT(_ file: URL, for app: TizenAppID) throws {
        let dir = root.appendingPathComponent("wgts").appendingPathComponent(app.value)
        // A revert reinstalls from this very library; replacing the folder would delete the source first.
        if file.resolvingSymlinksInPath().path.hasPrefix(dir.resolvingSymlinksInPath().path + "/") { return }
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: file, to: dir.appendingPathComponent(file.lastPathComponent))
    }

    public func wgt(for app: TizenAppID) -> URL? {
        let dir = root.appendingPathComponent("wgts").appendingPathComponent(app.value)
        return (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?.first
    }

    private func read(_ folder: URL) throws -> TizenRestorePoint {
        try Self.decoder.decode(TizenRestorePoint.self, from: Data(contentsOf: folder.appendingPathComponent("restore.json")))
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()
}
