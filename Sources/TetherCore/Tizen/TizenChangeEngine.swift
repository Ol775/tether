import Foundation

public struct TizenReport: Sendable {
    public let restorePoint: TizenRestorePoint
    public let applied: [TizenChange]
    /// Removals of apps that were already gone when the run started; nothing was sent for them.
    public let skipped: [TizenChange]
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
    /// The active profile's local `device-profile.xml`. When set, signed installs authorise the developer
    /// certificate natively (one `sdb push`, reverse-engineered from `tizen install-permit`) instead of the
    /// Tizen CLI. When nil, the CLI's `install-permit` is used as a fallback.
    private let deviceProfile: URL?
    private var active: Set<String> = []

    public init(sdb: SDBRunner, store: TizenRestorePointStore, log: ChangeLog, tizenCLI: URL? = nil, deviceProfile: URL? = nil) {
        self.sdb = sdb
        self.store = store
        self.log = log
        self.tizenCLI = tizenCLI
        self.deviceProfile = deviceProfile
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
                return TizenReport(restorePoint: rp, applied: [], skipped: [], failed: nil, pending: [], locked: [], cannotRestore: cannot, verified: true)
            }
            let report = try await run(plan, on: device, reason: "Revert: \(rp.reason)")
            return TizenReport(restorePoint: report.restorePoint, applied: report.applied, skipped: report.skipped, failed: report.failed, pending: report.pending,
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
        // sdb can exit 0 with error text, which parses to no apps at all; never treat that as "everything is already gone".
        if known.isEmpty, changes.contains(where: { if case .uninstall = $0 { true } else { false } }) {
            throw SDBError.commandFailed(code: 0, output: "The TV returned no app list, so nothing was changed. Check the connection and try again.")
        }
        let rp = try await store.create(device: device, reason: reason, apps: known, changes: changes)
        await log.append("\(device.serial): restore point \(rp.id) created (\(reason))")

        var applied: [TizenChange] = []
        var skipped: [TizenChange] = []
        var locked: [TizenAppID] = []
        var failed: (TizenChange, SDBError)?
        var pending: [TizenChange] = []
        for (i, change) in changes.enumerated() {
            do {
                switch change {
                case .uninstall(let id):
                    guard known.contains(where: { $0.id == id }) else { skipped.append(change); continue }
                    try await uninstall(id, on: device)
                    known = try await relist(device, previously: known)
                    if known.contains(where: { $0.id == id }) {
                        locked.append(id)
                        await log.append("\(device.serial): LOCKED \(id) (still installed after uninstall)")
                    } else {
                        applied.append(change)
                        await log.append("\(device.serial): uninstalled \(id)")
                    }
                case .install(let file), .installSigned(let file, _):
                    // The `tizen` CLI's own install command is unusable on real TVs here (a log4j
                    // misconfiguration corrupts its output and it fails to stage the package), so drive
                    // the platform installer directly: push the signed package, then `vd_appinstall` by
                    // the app id the TV will register — read from the package itself, not guessed.
                    let packageID = try await Self.packageAppID(of: file)
                    if case .installSigned(_, let expected) = change, expected != packageID {
                        throw SDBError.commandFailed(code: 1, output: "The package is \(packageID.value), not the expected \(expected.value); nothing was installed.")
                    }
                    if case .installSigned = change {
                        // A signed sideload needs the TV to trust this profile's certificate first.
                        try await permitInstall(on: device)
                    }
                    try await installPackage(file, appID: packageID, on: device)
                    known = try await relist(device, previously: known)
                    guard known.contains(where: { $0.id == packageID }) else {
                        throw SDBError.commandFailed(code: 1, output: "The TV did not confirm \(packageID.value) after installation.")
                    }
                    try await store.saveWGT(file, for: packageID)   // keep the signed package so a later removal can be undone
                    applied.append(change)
                    await log.append("\(device.serial): installed \(file.lastPathComponent) (\(packageID.value))")
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
            !snap.isEmpty && applied.allSatisfy { change in
                if case .uninstall(let id) = change { return !snap.contains { $0.id == id } }
                if case .installSigned(_, let id) = change { return snap.contains { $0.id == id } }
                return true
            }
        } ?? false
        return TizenReport(restorePoint: rp, applied: applied, skipped: skipped, failed: failed, pending: pending, locked: locked, cannotRestore: [], verified: verified)
    }

    static func checkInstallOutput(_ output: String, exitCode: Int32 = 0) throws {
        let lower = output.lowercased()
        let failure = exitCode != 0
            || ["error:", "failed", "cannot install", "can not install", "permission denied", "val[fail]", "key[error]"].contains { lower.contains($0) }
        let success = ["installed", "install completed", "success", "val[ok]"].contains { lower.contains($0) }
        guard success && !failure else { throw SDBError.classify(code: exitCode == 0 ? 1 : exitCode, output: output) }
    }

    /// The SDK's on-device staging directory that `vd_appinstall` reads from. A fixed filename is safe:
    /// `exclusive` serialises installs per TV, and it keeps spaces/encoding out of the pushed path.
    private static let stagingDir = "/home/owner/share/tmp/sdk_tools/tmp"

    /// Authorise this profile's developer certificate so the TV accepts the signed package.
    ///
    /// `tizen install-permit` is not a special service — reverse-engineered from the Tizen CLI, it pushes the
    /// active profile's `device-profile.xml` to the device's SDK tool path (`sdk_toolpath` from `sdb capability`;
    /// `/home/developer` on pre-3.0 firmware). We do exactly that when a local `device-profile.xml` is known,
    /// and fall back to the CLI otherwise.
    private func permitInstall(on device: TizenDevice) async throws {
        guard let deviceProfile else {
            guard let cli = tizenCLI else { throw SDBError.toolsMissing }
            let permit = try await TizenCLI.run(cli, ["install-permit", "-s", device.serial], timeout: .seconds(60))
            guard permit.status == 0 else { throw SDBError.classify(code: permit.status, output: permit.err + permit.out) }
            return
        }
        let capability = TizenParsers.capability(try await sdb.run(["capability"], serial: device.serial))
        let target = (capability["sdk_toolpath"].map { $0.isEmpty ? nil : $0 } ?? nil) ?? "/home/developer"
        let out = try await sdb.run(["push", deviceProfile.path, "\(target)/device-profile.xml"],
                                    serial: device.serial, timeout: ADBRunner.transferTimeout)
        guard out.lowercased().contains("pushed") else {
            throw SDBError.commandFailed(code: 1, output: "Couldn't authorise the developer certificate on the TV: \(out)")
        }
    }

    /// Push the package, then trigger the platform installer by app id. This is what the `tizen` CLI
    /// does internally, minus its broken local staging step.
    private func installPackage(_ file: URL, appID: TizenAppID, on device: TizenDevice) async throws {
        let remote = "\(Self.stagingDir)/tether-install.\(file.pathExtension.lowercased())"
        _ = try await sdb.run(["push", file.path, remote], serial: device.serial, timeout: ADBRunner.transferTimeout)
        let out = try await sdb.run(["shell", "0", "vd_appinstall", appID.value, remote], serial: device.serial, timeout: ADBRunner.transferTimeout)
        try Self.checkInstallOutput(out)
    }

    /// The app id the TV registers for a package, read from the package itself: `config.xml` for a
    /// `.wgt` web app, `tizen-manifest.xml` for a `.tpk`. `vd_appinstall` needs it up front.
    static func packageAppID(of file: URL) async throws -> TizenAppID {
        func entry(_ name: String) async -> String? {
            let r = try? await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-p", file.path, name], timeout: .seconds(30))
            return r?.status == 0 ? r?.out : nil
        }
        if let xml = await entry("config.xml"),
           let m = xml.firstMatch(of: #/<tizen:application\b[^>]*\bid="([^"]+)"/#), let id = TizenAppID(String(m.1)) { return id }
        if let xml = await entry("tizen-manifest.xml"),
           let m = xml.firstMatch(of: #/<ui-application\b[^>]*\bappid="([^"]+)"/#), let id = TizenAppID(String(m.1)) { return id }
        throw SDBError.commandFailed(code: 1, output: "Couldn't read the Tizen application id from \(file.lastPathComponent).")
    }

    /// Re-reads the app list after a change. An empty list when there were apps a moment ago is a failed read, not a result.
    private func relist(_ device: TizenDevice, previously: [TizenApp]) async throws -> [TizenApp] {
        let now = try await listApps(device)
        if now.isEmpty && !previously.isEmpty { throw SDBError.notConnected }
        return now
    }

    /// Firmware that lacks the command says so in its output (often with exit 0), so the text decides, not the exit code.
    private static func commandMissing(_ output: String) -> Bool {
        let t = output.lowercased()
        return t.contains("not found") || t.contains("unsupported") || t.contains("inaccessible")
    }

    /// `vd_appuninstall` first; older or different firmware may lack it, so fall back to the `tizen` CLI.
    private func uninstall(_ id: TizenAppID, on device: TizenDevice) async throws {
        let missing: Bool
        do {
            missing = Self.commandMissing(try await sdb.run(["shell", "0", "vd_appuninstall", id.value], serial: device.serial))
        } catch SDBError.commandFailed {
            missing = true
        }
        if missing {
            guard let cli = tizenCLI else { throw SDBError.toolsMissing }
            let r = try await TizenCLI.run(cli, ["uninstall", "-p", id.value, "-s", device.serial], timeout: .seconds(60))
            guard r.status == 0 else { throw SDBError.classify(code: r.status, output: r.err + r.out) }
        }
    }
}
