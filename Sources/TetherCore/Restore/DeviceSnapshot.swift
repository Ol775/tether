/// Live device state that restore points record and reverts compare against.
public struct DeviceSnapshot: Equatable, Sendable {
    public var packages: [PackageSnapshot]
    /// namespace (global | secure | system) → key → value
    public var settings: [String: [String: String]]
    /// nil = no user override
    public var density: Int?
    public var home: String?
    /// The panel's native density, from `wm density`.
    public var physicalDensity: Int? = nil

    public static func capture(adb: ADBRunner, serial: String) async throws -> DeviceSnapshot {
        async let all = adb.run(["shell", "pm", "list", "packages", "-u", "--user", "0"], serial: serial)
        async let installed = adb.run(["shell", "pm", "list", "packages", "--user", "0"], serial: serial)
        async let disabled = adb.run(["shell", "pm", "list", "packages", "-d", "--user", "0"], serial: serial)
        let packages = Parsers.packages(all: try await all, installed: try await installed, disabled: try await disabled)

        var settings: [String: [String: String]] = [:]
        for ns in SettingNamespace.allCases {
            settings[ns.rawValue] = Parsers.settings(try await adb.run(["shell", "settings", "list", ns.rawValue], serial: serial))
        }
        let wm = try await adb.run(["shell", "wm", "density"], serial: serial)
        let home = try? await homeComponent(adb, serial)
        return DeviceSnapshot(packages: packages, settings: settings, density: Parsers.densityOverride(wm), home: home,
                              physicalDensity: Parsers.physicalDensity(wm))
    }

    public func state(of name: PackageName) -> PackageState? {
        packages.first { $0.name == name }?.state
    }

    /// Whether `change` is already reflected in this snapshot.
    func satisfies(_ change: Change) -> Bool {
        func present(_ p: PackageName) -> Bool { state(of: p) == .enabled || state(of: p) == .disabled }
        switch change {
        case .removePackage(let p): return !present(p)
        case .restorePackage(let p): return present(p)
        case .setSetting(let ns, let key, let value): return settings[ns.rawValue]?[key] == value
        case .deleteSetting(let ns, let key): return settings[ns.rawValue]?[key] == nil
        case .setDensity(let dpi): return density == dpi
        case .setHome, .revokePermission, .grantPermission: return true   // not cheaply checkable
        }
    }

    public var installedNames: Set<PackageName> {
        Set(packages.filter { $0.state != .removedForUser }.map(\.name))
    }

    private static func homeComponent(_ adb: ADBRunner, _ serial: String) async throws -> String? {
        let out = try await adb.run(["shell", "cmd", "package", "resolve-activity", "--brief",
                                     "-a", "android.intent.action.MAIN", "-c", "android.intent.category.HOME"], serial: serial)
        return out.split(whereSeparator: \.isNewline).last { $0.contains("/") }.map(String.init)
    }
}
