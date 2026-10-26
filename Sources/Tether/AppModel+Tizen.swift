import Foundation
import TetherCore

extension AppModel {
    var selectedTizen: TizenDevice? { tizenDevices.first { $0.serial == selectedTizenSerial } }
    var tizenLocked: Set<TizenAppID> { selectedTizen.flatMap { lockedByDevice[$0.deviceID] } ?? [] }

    // MARK: - devices

    func pollTizen() async {
        guard !isBusy, tizenToolsReady else { return }
        let generation = connectionGeneration
        guard let found = try? await tizenManager.devices(), !isBusy, generation == connectionGeneration, found != tizenDevices else { return }
        tizenDevices = found
        if let serial = selectedTizenSerial, !found.contains(where: { $0.serial == serial }) { selectedTizenSerial = nil }
        if selected == nil && selectedTizen == nil { selectedTizenSerial = found.first?.serial }
        try? await reloadTizen()
    }

    func selectTizen(_ serial: String) async {
        guard !isBusy else { return }
        selectedTizenSerial = serial
        await run("Couldn't read the TV") { try await reloadTizen() }
    }

    func connectTizen(host: String, port: Int) async throws {
        guard canManageConnections else { throw TizenError.busy }
        isBusy = true
        do { try await tizenManager.connect(host: host, port: port) }
        catch { isBusy = false; throw error }
        isBusy = false
        await pollTizen()
    }

    func disconnectTizen() async {
        guard let tv = selectedTizen else { return }
        await run {
            try await tizenManager.disconnect(serial: tv.serial)
            tizenDevices.removeAll { $0.serial == tv.serial }
            selectedTizenSerial = nil
        }
    }

    func reloadTizen() async throws {
        guard let tv = selectedTizen else { tizenApps = []; tizenRestorePoints = []; return }
        do {
            let apps = TizenParsers.apps(try await sdb.run(["shell", "0", "applist"], serial: tv.serial))
            let catalog = try TizenCatalog.bundled()
            let points = await tizenStore.list().filter { $0.device.deviceID == tv.deviceID }
            let certificate = await certificates.state(for: tv)
            // These awaits can be slow; if the user switched TVs meanwhile, this answer belongs to the old one.
            guard selectedTizenSerial == tv.serial else { return }
            tizenApps = apps; tizenCatalog = catalog; tizenRestorePoints = points; certificateState = certificate
        } catch {
            if selectedTizenSerial == tv.serial { tizenApps = [] }   // don't leave a stale picture of a TV we can no longer read
            throw error
        }
    }

    // MARK: - changes

    func applyTizen(_ changes: [TizenChange], reason: String) async {
        guard let tv = selectedTizen else { return }
        await run("Couldn't change the TV") {
            let report = try await tizenEngine.apply(changes, on: tv, reason: reason)
            rememberLocked(report.locked, on: tv)
            tizenReportToShow = TizenReportBox(title: reason, report: report)   // before reload: if the TV just dropped, the report is all the user has
            try? await reloadTizen()
        }
    }

    func revertTizen(_ rp: TizenRestorePoint, addressChangeConfirmed: Bool = false) async {
        guard let tv = selectedTizen else { return }
        if rp.device.serial != tv.serial && !addressChangeConfirmed {
            tizenAddressChangeRevert = rp
            return
        }
        await run("Couldn't revert") {
            let report = try await tizenEngine.revert(rp, on: tv)
            tizenReportToShow = TizenReportBox(title: "Reverted: \(rp.reason)", report: report)
            try? await reloadTizen()
        }
    }

    func deleteTizenRestorePoint(_ rp: TizenRestorePoint) async {
        await run("Couldn't delete") { try await tizenStore.delete(rp.id); try await reloadTizen() }
    }

    // MARK: - Samsung tools

    func setUpSamsungTools(acceptingLicense: Bool) async {
        toolsProgress = []
        await run("Couldn't set up Samsung's tools") {
            try await tools.install(acceptingLicense: acceptingLicense) { @Sendable [weak self] line in
                Task { @MainActor in self?.toolsProgress.append(line) }
            }
            tizenToolsReady = true
            await pollTizen()
        }
    }

    func refreshTizenCertificate() async {
        guard let tv = selectedTizen else { return }
        let state = await certificates.state(for: tv)
        guard selectedTizen?.serial == tv.serial else { return }
        certificateState = state
    }

    // MARK: - remembered locks

    private func rememberLocked(_ ids: [TizenAppID], on tv: TizenDevice) {
        guard !ids.isEmpty else { return }
        lockedByDevice[tv.deviceID, default: []].formUnion(ids)
        let plain = lockedByDevice.mapValues { $0.map(\.value).sorted() }
        if let data = try? JSONEncoder().encode(plain) {
            try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
            try? data.write(to: supportDir.appendingPathComponent("tizen-locked.json"), options: .atomic)
        }
    }

    static func loadLocked(_ file: URL) -> [String: Set<TizenAppID>] {
        guard let data = try? Data(contentsOf: file), let plain = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return plain.mapValues { Set($0.compactMap(TizenAppID.init)) }
    }
}
