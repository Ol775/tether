import Foundation

/// One folder per snapshot: `<root>/<id>/restore.json` plus `apks/<package>/*.apk`.
public actor RestorePointStore {
    private let root: URL
    private let adb: ADBRunner

    public init(root: URL, adb: ADBRunner) {
        self.root = root
        self.adb = adb
    }

    public func create(device: DeviceProfile, reason: String, pullAPKsFor: [PackageName]) async throws -> RestorePoint {
        let serial = device.serial
        async let all = adb.run(["shell", "pm", "list", "packages", "-u", "--user", "0"], serial: serial)
        async let installed = adb.run(["shell", "pm", "list", "packages", "--user", "0"], serial: serial)
        async let disabled = adb.run(["shell", "pm", "list", "packages", "-d", "--user", "0"], serial: serial)
        let packages = Parsers.packages(all: try await all, installed: try await installed, disabled: try await disabled)

        var settings: [String: [String: String]] = [:]
        for ns in ["global", "secure", "system"] {
            settings[ns] = Parsers.settings(try await adb.run(["shell", "settings", "list", ns], serial: serial))
        }
        let density = Parsers.densityOverride(try await adb.run(["shell", "wm", "density"], serial: serial))
        let home = try? await Self.homeComponent(adb, serial)

        let id = UUID()
        let folder = root.appendingPathComponent(id.uuidString)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var apks: [String: [String]] = [:]
            for pkg in pullAPKsFor { apks[pkg.value] = try await pull(pkg, into: folder, serial: serial) }

            let now = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 * 1000).rounded() / 1000)
            let rp = RestorePoint(id: id, createdAt: now, reason: reason, profile: device, packages: packages,
                                  settings: settings, apks: apks, density: density, home: home)
            try Self.encoder.encode(rp).write(to: folder.appendingPathComponent("restore.json"), options: .atomic)
            try verify(rp, in: folder)
            return rp
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    public func list() throws -> [RestorePoint] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { try? read($0) }.sorted { $0.createdAt > $1.createdAt }
    }

    public func load(_ id: UUID) throws -> RestorePoint {
        let folder = root.appendingPathComponent(id.uuidString)
        guard FileManager.default.fileExists(atPath: folder.path) else { throw RestoreError.notFound(id) }
        return try read(folder)
    }

    public func apkURLs(_ rp: RestorePoint, for name: PackageName) -> [URL] {
        (rp.apks[name.value] ?? []).map { root.appendingPathComponent(rp.id.uuidString).appendingPathComponent($0) }
    }

    public func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: root.appendingPathComponent(id.uuidString))
    }

    // MARK: - internals

    private func pull(_ pkg: PackageName, into folder: URL, serial: String) async throws -> [String] {
        let remote = try await adb.run(["shell", "pm", "path", pkg.value], serial: serial)
            .split(whereSeparator: \.isNewline)
            .filter { $0.hasPrefix("package:") }
            .map { String($0.dropFirst(8)) }
        guard !remote.isEmpty else { throw RestoreError.unverified("no APK path for \(pkg)") }
        let dir = folder.appendingPathComponent("apks").appendingPathComponent(pkg.value)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var relative: [String] = []
        for path in remote {
            let name = (path as NSString).lastPathComponent
            _ = try await adb.run(["pull", path, dir.appendingPathComponent(name).path], serial: serial)
            relative.append("apks/\(pkg.value)/\(name)")
        }
        return relative
    }

    private func verify(_ rp: RestorePoint, in folder: URL) throws {
        guard try read(folder) == rp else { throw RestoreError.unverified("restore.json did not read back identically") }
        for path in rp.apks.values.joined() {
            let size = (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(path).path)[.size] as? Int) ?? 0
            guard size > 0 else { throw RestoreError.unverified("\(path) is missing or empty") }
        }
    }

    private func read(_ folder: URL) throws -> RestorePoint {
        try Self.decoder.decode(RestorePoint.self, from: Data(contentsOf: folder.appendingPathComponent("restore.json")))
    }

    private static func homeComponent(_ adb: ADBRunner, _ serial: String) async throws -> String? {
        let out = try await adb.run(["shell", "cmd", "package", "resolve-activity", "--brief",
                                     "-a", "android.intent.action.MAIN", "-c", "android.intent.category.HOME"], serial: serial)
        return out.split(whereSeparator: \.isNewline).last { $0.contains("/") }.map(String.init)
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
