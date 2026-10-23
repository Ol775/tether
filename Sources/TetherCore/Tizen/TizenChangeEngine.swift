import Foundation

public struct TizenReport: Sendable {
    public let restorePoint: TizenRestorePoint
    public let applied: [TizenChange]
    public let failed: (TizenChange, SDBError)?
    public let pending: [TizenChange]
    /// Apps the TV refused to remove (exit 0, still listed).
    public let locked: [TizenAppID]
    /// Revert only: apps Tether has no signed package for, so they cannot be put back from here.
    public let cannotRestore: [TizenAppID]
    /// True when a re-read of the TV confirms every applied removal.
    public let verified: Bool
}

/// The only path to mutating `sdb` commands: restore point first, apply in order, stop on a failed
/// connection, re-read to verify. A refused removal is reported as locked, not as applied.
public actor TizenChangeEngine {
    private let sdb: SDBRunner
    private let store: TizenRestorePointStore
    private let log: ChangeLog
    private let tizenCLI: URL?
    private var active: Set<String> = []

    public init(sdb: SDBRunner, store: TizenRestorePointStore, log: ChangeLog, tizenCLI: URL? = nil) {
        self.sdb = sdb
        self.store = store
        self.log = log
        self.tizenCLI = tizenCLI
    }

    public func apply(_ changes: [TizenChange], on device: TizenDevice, reason: String) async throws -> TizenReport {
        try await exclusive(device) { try await run(changes, on: device, reason: reason) }
    }

    /// Puts back what `rp` removed, for apps Tether installed itself. Preloaded apps cannot be reinstalled from here.
    public func revert(_ rp: TizenRestorePoint, on device: TizenDevice) async throws -> TizenReport {
        guard rp.device.deviceID == device.deviceID, rp.device.model == device.model else { throw TizenError.wrongDevice }
        return try await exclusive(device) {
            let current = Set(try await listApps(device).map(\.id))
            var plan: [TizenChange] = []
            var cannot: [TizenAppID] = []
            for case .uninstall(let id) in rp.changes where !current.contains(id) {
                if let file = await store.wgt(for: id) { plan.append(.install(wgt: file)) } else { cannot.append(id) }
            }
            if plan.isEmpty {
                guard !cannot.isEmpty else { throw TizenError.nothingToDo }
                return TizenReport(restorePoint: rp, applied: [], failed: nil, pending: [], locked: [], cannotRestore: cannot, verified: true)
            }
            let report = try await run(plan, on: device, reason: "Revert: \(rp.reason)")
            return TizenReport(restorePoint: report.restorePoint, applied: report.applied, failed: report.failed, pending: report.pending,
                               locked: report.locked, cannotRestore: cannot, verified: report.verified)
        }
    }

    /// The actor is reentrant across awaits, so two runs on one TV could interleave; refuse the second.
    private func exclusive<T>(_ device: TizenDevice, _ body: () async throws -> T) async throws -> T {
        guard active.insert(device.deviceID).inserted else { throw TizenError.busy }
        defer { active.remove(device.deviceID) }
        return try await body()
    }

    private func listApps(_ device: TizenDevice) async throws -> [TizenApp] {
        TizenParsers.apps(try await sdb.run(["shell", "0", "applist"], serial: device.serial))
    }

    private func run(_ changes: [TizenChange], on device: TizenDevice, reason: String) async throws -> TizenReport {
        for change in changes { try change.validate() }
        guard !changes.isEmpty else { throw TizenError.nothingToDo }

        var known = try await listApps(device)
        let rp = try await store.create(device: device, reason: reason, apps: known, changes: changes)
        await log.append("\(device.serial): restore point \(rp.id) created (\(reason))")

        var applied: [TizenChange] = []
        var locked: [TizenAppID] = []
        var failed: (TizenChange, SDBError)?
        var pending: [TizenChange] = []
        for (i, change) in changes.enumerated() {
            do {
                switch change {
                case .uninstall(let id):
                    guard known.contains(where: { $0.id == id }) else { applied.append(change); continue }
                    try await uninstall(id, on: device)
                    known = try await listApps(device)
                    if known.contains(where: { $0.id == id }) {
                        locked.append(id)
                        await log.append("\(device.serial): LOCKED \(id) (still installed after uninstall)")
                    } else {
                        applied.append(change)
                        await log.append("\(device.serial): uninstalled \(id)")
                    }
                case .install(let file):
                    let before = Set(known.map(\.id))
                    _ = try await sdb.run(["install", file.path], serial: device.serial, timeout: ADBRunner.transferTimeout)
                    known = try await listApps(device)
                    let added = known.map(\.id).filter { !before.contains($0) }
                    if added.count == 1 { try await store.saveWGT(file, for: added[0]) }   // keep the signed package so a later removal can be undone
                    applied.append(change)
                    await log.append("\(device.serial): installed \(file.lastPathComponent)")
                }
            } catch {
                let sdbError = (error as? SDBError) ?? .commandFailed(code: 1, output: "\(error)")
                failed = (change, sdbError)
                pending = Array(changes[(i + 1)...])
                await log.append("\(device.serial): FAILED \(change): \(sdbError)")
                break
            }
        }

        let after = try? await listApps(device)
        let verified = after.map { snap in
            applied.allSatisfy { change in
                if case .uninstall(let id) = change { return !snap.contains { $0.id == id } }
                return true
            }
        } ?? false
        return TizenReport(restorePoint: rp, applied: applied, failed: failed, pending: pending, locked: locked, cannotRestore: [], verified: verified)
    }

    /// `vd_appuninstall` first; older or different firmware may lack it, so fall back to the `tizen` CLI.
    private func uninstall(_ id: TizenAppID, on device: TizenDevice) async throws {
        do {
            _ = try await sdb.run(["shell", "0", "vd_appuninstall", id.value], serial: device.serial)
        } catch SDBError.commandFailed {
            guard let cli = tizenCLI else { throw SDBError.toolsMissing }
            let r = try await ProcessRunner.run(cli, ["uninstall", "-p", id.value, "-t", device.serial], timeout: .seconds(60))
            guard r.status == 0 else { throw SDBError.classify(code: r.status, output: r.err + r.out) }
        }
    }
}
