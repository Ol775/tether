import Foundation

public struct ChangeReport: Sendable {
    public let restorePoint: RestorePoint
    public let applied: [Change]
    public let failed: (Change, ADBError)?
    public let pending: [Change]
    /// True when a re-read of the device confirms every applied change.
    public let verified: Bool
}

/// The only path to mutating commands: snapshot first, apply in order, stop on failure, re-read to verify.
public actor ChangeEngine {
    private let adb: ADBRunner
    private let store: RestorePointStore
    private let log: ChangeLog

    public init(adb: ADBRunner, store: RestorePointStore, log: ChangeLog) {
        self.adb = adb
        self.store = store
        self.log = log
    }

    public func apply(_ changes: [Change], on device: DeviceProfile, reason: String) async throws -> ChangeReport {
        try await run(changes, on: device, reason: reason, fallback: nil)
    }

    /// Undoes what `rp` was taken for. Itself takes a restore point, so a revert can be reverted.
    public func revert(_ rp: RestorePoint, on device: DeviceProfile) async throws -> ChangeReport {
        guard rp.profile.serial == device.serial else { throw ChangeError.wrongDevice }
        let current = try await DeviceSnapshot.capture(adb: adb, serial: device.serial)
        return try await run(RevertPlanner.plan(rp, current: current), on: device, reason: "Revert: \(rp.reason)", fallback: rp)
    }

    private func run(_ changes: [Change], on device: DeviceProfile, reason: String, fallback: RestorePoint?) async throws -> ChangeReport {
        for change in changes { _ = try change.adbArguments() }
        guard !changes.isEmpty else { throw ChangeError.empty }

        let before = try await DeviceSnapshot.capture(adb: adb, serial: device.serial)
        let toPull = changes.compactMap { change -> PackageName? in
            guard case .removePackage(let p) = change, Self.isPresent(before.state(of: p)) else { return nil }
            return p
        }
        let rp = try await store.create(device: device, reason: reason, pullAPKsFor: toPull, changes: changes)
        await log.append("\(device.serial): restore point \(rp.id) created (\(reason))")

        var applied: [Change] = []
        var failed: (Change, ADBError)?
        var pending: [Change] = []
        for (i, change) in changes.enumerated() {
            if Self.alreadyDone(change, before) { applied.append(change); continue }
            do {
                try await execute(change, serial: device.serial, fallback: fallback)
                applied.append(change)
                await log.append("\(device.serial): applied \(change) via adb \((try? change.adbArguments().joined(separator: " ")) ?? "")")
            } catch let error as ADBError {
                failed = (change, error)
                pending = Array(changes[(i + 1)...])
                await log.append("\(device.serial): FAILED \(change): \(error)")
                break
            }
        }

        let after = try? await DeviceSnapshot.capture(adb: adb, serial: device.serial)
        let verified = after.map { snap in applied.allSatisfy { Self.holds($0, in: snap) } } ?? false
        return ChangeReport(restorePoint: rp, applied: applied, failed: failed, pending: pending, verified: verified)
    }

    private func execute(_ change: Change, serial: String, fallback: RestorePoint?) async throws {
        do {
            _ = try await adb.run(try change.adbArguments(), serial: serial)
        } catch let error as ADBError {
            // install-existing fails when the system image no longer has the package: reinstall the pulled APKs.
            guard case .restorePackage(let p) = change, let fallback else { throw error }
            let apks = await store.apkURLs(fallback, for: p).map(\.path)
            guard !apks.isEmpty else { throw error }
            _ = try await adb.run((apks.count == 1 ? ["install", "-r"] : ["install-multiple", "-r"]) + apks, serial: serial)
        }
    }

    private static func isPresent(_ s: PackageState?) -> Bool { s == .enabled || s == .disabled }

    private static func alreadyDone(_ change: Change, _ s: DeviceSnapshot) -> Bool {
        switch change {
        case .removePackage(let p): s.state(of: p) == .removedForUser
        case .restorePackage(let p): isPresent(s.state(of: p))
        default: false
        }
    }

    private static func holds(_ change: Change, in s: DeviceSnapshot) -> Bool {
        switch change {
        case .removePackage(let p): !isPresent(s.state(of: p))
        case .restorePackage(let p): isPresent(s.state(of: p))
        case .setSetting(let ns, let key, let value): s.settings[ns.rawValue]?[key] == value
        case .deleteSetting(let ns, let key): s.settings[ns.rawValue]?[key] == nil
        case .setDensity(let dpi): s.density == dpi
        case .setHome, .revokePermission, .grantPermission: true   // not cheaply checkable
        }
    }
}
