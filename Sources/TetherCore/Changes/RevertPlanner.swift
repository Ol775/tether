/// Works out what undoes a restore point's changes, using only the keys it touched.
public enum RevertPlanner {
    public static func plan(_ rp: RestorePoint, current: DeviceSnapshot) -> [Change] {
        var plan: [Change] = []
        func add(_ c: Change) { if !plan.contains(c) { plan.append(c) } }
        func present(_ s: PackageState?) -> Bool { s == .enabled || s == .disabled }
        let before = DeviceSnapshot(packages: rp.packages, settings: rp.settings, density: rp.density, home: rp.home)

        for change in rp.changes {
            switch change {
            case .removePackage(let p):
                if present(before.state(of: p)), !present(current.state(of: p)) { add(.restorePackage(p)) }
            case .restorePackage(let p):
                if !present(before.state(of: p)), present(current.state(of: p)) { add(.removePackage(p)) }
            case .setSetting(let ns, let key, _), .deleteSetting(let ns, let key):
                let previous = before.settings[ns.rawValue]?[key], now = current.settings[ns.rawValue]?[key]
                if let previous { if now != previous { add(.setSetting(ns: ns, key: key, value: previous)) } }
                else if now != nil { add(.deleteSetting(ns: ns, key: key)) }
            case .setDensity:
                if current.density != before.density { add(.setDensity(before.density)) }
            case .setHome:
                if let previous = before.home, current.home != previous { add(.setHome(previous)) }
            case .revokePermission(let p, let perm): add(.grantPermission(p, perm))
            case .grantPermission(let p, let perm): add(.revokePermission(p, perm))
            }
        }
        return plan
    }
}
