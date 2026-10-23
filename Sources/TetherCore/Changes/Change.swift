public enum SettingNamespace: String, Codable, CaseIterable, Sendable {
    case global, secure, system
}

public enum Change: Codable, Hashable, Sendable {
    case removePackage(PackageName)
    case restorePackage(PackageName)
    case setSetting(ns: SettingNamespace, key: String, value: String)
    case deleteSetting(ns: SettingNamespace, key: String)
    /// nil resets to the physical density.
    case setDensity(Int?)
    /// Default launcher component, e.g. `com.spocky.projengmenu/.ui.home.MainActivity`.
    case setHome(String)
    case revokePermission(PackageName, String)
    case grantPermission(PackageName, String)
}

public enum ChangeError: Error, Equatable, Sendable {
    case unsafeValue
    case wrongDevice
    case empty
    case busy
}

extension Change {
    /// adb arguments for this change. adb joins shell args into one remote command line, so
    /// every free-form value is checked against a strict character set first.
    func adbArguments() throws -> [String] {
        switch self {
        case .removePackage(let p): return ["shell", "pm", "uninstall", "-k", "--user", "0", p.value]
        case .restorePackage(let p): return ["shell", "cmd", "package", "install-existing", "--user", "0", p.value]
        case .setSetting(let ns, let key, let value):
            return ["shell", "settings", "put", ns.rawValue, try Self.safe(key, "_.:-"), try Self.safe(value, "_.:,=/@+-")]
        case .deleteSetting(let ns, let key):
            return ["shell", "settings", "delete", ns.rawValue, try Self.safe(key, "_.:-")]
        case .setDensity(let dpi):
            guard let dpi else { return ["shell", "wm", "density", "reset"] }
            guard (72...960).contains(dpi) else { throw ChangeError.unsafeValue }
            return ["shell", "wm", "density", String(dpi)]
        case .setHome(let component):
            return ["shell", "cmd", "package", "set-home-activity", "--user", "0", try Self.safe(component, "_./")]
        case .revokePermission(let p, let perm): return ["shell", "pm", "revoke", p.value, try Self.safe(perm, "_.")]
        case .grantPermission(let p, let perm): return ["shell", "pm", "grant", p.value, try Self.safe(perm, "_.")]
        }
    }

    private static func safe(_ s: String, _ extra: String) throws -> String {
        let ok = !s.isEmpty && s.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0) || extra.unicodeScalars.contains($0)) }
        guard ok else { throw ChangeError.unsafeValue }
        return s
    }
}
