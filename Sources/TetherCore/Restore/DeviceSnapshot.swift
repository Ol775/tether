/// Live device state that restore points record and reverts compare against.
public struct DeviceSnapshot: Equatable, Sendable {
    public var packages: [PackageSnapshot]
    /// namespace (global | secure | system) → key → value
    public var settings: [String: [String: String]]
    /// nil = no user override
    public var density: Int?
    public var home: String?

    public static func capture(adb: ADBRunner, serial: String) async throws -> DeviceSnapshot {
        async let all = adb.run(["shell", "pm", "list", "packages", "-u", "--user", "0"], serial: serial)
        async let installed = adb.run(["shell", "pm", "list", "packages", "--user", "0"], serial: serial)
        async let disabled = adb.run(["shell", "pm", "list", "packages", "-d", "--user", "0"], serial: serial)
        let packages = Parsers.packages(all: try await all, installed: try await installed, disabled: try await disabled)

        var settings: [String: [String: String]] = [:]
        for ns in SettingNamespace.allCases {
            settings[ns.rawValue] = Parsers.settings(try await adb.run(["shell", "settings", "list", ns.rawValue], serial: serial))
        }
        let density = Parsers.densityOverride(try await adb.run(["shell", "wm", "density"], serial: serial))
        let home = try? await homeComponent(adb, serial)
        return DeviceSnapshot(packages: packages, settings: settings, density: density, home: home)
    }

    public func state(of name: PackageName) -> PackageState? {
        packages.first { $0.name == name }?.state
    }

    var installedNames: Set<PackageName> {
        Set(packages.filter { $0.state != .removedForUser }.map(\.name))
    }

    private static func homeComponent(_ adb: ADBRunner, _ serial: String) async throws -> String? {
        let out = try await adb.run(["shell", "cmd", "package", "resolve-activity", "--brief",
                                     "-a", "android.intent.action.MAIN", "-c", "android.intent.category.HOME"], serial: serial)
        return out.split(whereSeparator: \.isNewline).last { $0.contains("/") }.map(String.init)
    }
}
