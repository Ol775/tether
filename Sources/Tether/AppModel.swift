import AppKit
import Foundation
import Observation
import TetherCore

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct ReportBox: Identifiable {
    let id = UUID()
    let title: String
    let report: ChangeReport
}

struct TizenReportBox: Identifiable {
    let id = UUID()
    let title: String
    let report: TizenReport
}

struct Toast: Identifiable {
    let id = UUID()
    let message: String
    let undo: RestorePoint?
}

@MainActor
final class ChoiceRequest: Identifiable {
    let id = UUID()
    let options: [ReleaseAsset]
    private var continuation: CheckedContinuation<ReleaseAsset?, Never>?

    init(options: [ReleaseAsset], continuation: CheckedContinuation<ReleaseAsset?, Never>) {
        self.options = options
        self.continuation = continuation
    }

    func resolve(_ asset: ReleaseAsset?) {
        continuation?.resume(returning: asset)
        continuation = nil
    }
}

enum Pane: String, CaseIterable, Identifiable {
    case overview, debloat, tweaks, apps, backups, console
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// Sections a Tizen TV supports (no adb tweaks or console).
    static let tizenPanes: [Pane] = [.overview, .debloat, .apps, .backups]
    var symbol: String {
        switch self {
        case .overview: "info.circle"
        case .debloat: "trash.slash"
        case .tweaks: "slider.horizontal.3"
        case .apps: "square.and.arrow.down"
        case .backups: "clock.arrow.circlepath"
        case .console: "terminal"
        }
    }
}

@MainActor @Observable
final class AppModel {
    var devices: [DeviceProfile] = []
    var selectedSerial: String? {
        // Never show one device's packages and settings while actions would go to another.
        didSet {
            guard oldValue != selectedSerial else { return }
            snapshot = nil; restorePoints = []; thirdPartyApps = []
            if selectedSerial != nil { selectedTizenSerial = nil }   // one device at a time
        }
    }
    var selectedTizenSerial: String? {
        didSet {
            guard oldValue != selectedTizenSerial else { return }
            tizenApps = []; tizenRestorePoints = []; certificateState = nil
            if selectedTizenSerial != nil {
                selectedSerial = nil
                if !Pane.tizenPanes.contains(section) { section = .overview }
            }
        }
    }
    var tizenDevices: [TizenDevice] = []
    var tizenApps: [TizenApp] = []
    var tizenRestorePoints: [TizenRestorePoint] = []
    var tizenCatalog: TizenCatalog?
    var certificateState: CertificateState?
    var tizenToolsReady = false
    var toolsProgress: [String] = []
    var showTizenSetup = false
    var tizenReportToShow: TizenReportBox?
    var tizenAddressChangeRevert: TizenRestorePoint?
    /// Apps each TV refused to remove, by device id; remembered so the UI stops offering them.
    var lockedByDevice: [String: Set<TizenAppID>] = [:]
    var section: Pane = .overview
    var snapshot: DeviceSnapshot?
    var catalog: Catalog?
    var restorePoints: [RestorePoint] = []
    var thirdPartyApps: [PackageName] = []
    var isBusy = false
    var alert: AppAlert?
    var reportToShow: ReportBox?
    var toast: Toast?
    var showPairing = false
    var showInspector = true
    var inspected: CatalogEntry?
    var pendingChoice: ChoiceRequest?
    /// A restore point made at a different address; held until the user confirms it is the same device.
    var addressChangeRevert: RestorePoint?

    private let adb: ADBRunner
    private let deviceManager: DeviceManager
    private let store: RestorePointStore
    private let engine: ChangeEngine
    private let log: ChangeLog
    private let installer: Installer
    private let catalogStore: CatalogStore
    let sdb: SDBRunner
    let tizenManager: TizenManager
    let tizenStore: TizenRestorePointStore
    let tizenEngine: TizenChangeEngine
    let tools: SamsungTools
    let certificates: TizenCertificates
    let tizenOverride: Bool
    let supportDir: URL

    init() {
        let env = ProcessInfo.processInfo.environment
        supportDir = env["TETHER_SUPPORT"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tether")
        adb = ADBRunner(executable: Self.adbURL(env))
        deviceManager = DeviceManager(adb: adb)
        store = RestorePointStore(root: supportDir.appendingPathComponent("RestorePoints"), adb: adb)
        log = ChangeLog(file: supportDir.appendingPathComponent("changes.jsonl"))
        engine = ChangeEngine(adb: adb, store: store, log: log)
        installer = Installer(adb: adb)
        section = Pane(rawValue: env["TETHER_PANE"] ?? "") ?? .overview   // lets scripts/screenshots.sh open each pane
        catalogStore = CatalogStore(overrideDir: supportDir)

        let samsungHome = supportDir.appendingPathComponent("samsung")
        tools = SamsungTools(home: samsungHome)
        tizenOverride = env["TETHER_SDB"] != nil   // demo/tests point at a scripted sdb instead of Samsung's tools
        sdb = SDBRunner(executable: env["TETHER_SDB"].map { URL(fileURLWithPath: $0) } ?? samsungHome.appendingPathComponent("tizen-studio/tools/sdb"))
        tizenManager = TizenManager(sdb: sdb)
        tizenStore = TizenRestorePointStore(root: supportDir.appendingPathComponent("TizenRestorePoints"))
        tizenEngine = TizenChangeEngine(sdb: sdb, store: tizenStore, log: log, tizenCLI: samsungHome.appendingPathComponent("tizen-studio/tools/ide/bin/tizen"))
        certificates = TizenCertificates(tools: tools)
        tizenToolsReady = tizenOverride || tools.isInstalled
        lockedByDevice = Self.loadLocked(supportDir.appendingPathComponent("tizen-locked.json"))
    }

    private static func adbURL(_ env: [String: String]) -> URL {
        if let path = env["TETHER_ADB"] { return URL(fileURLWithPath: path) }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("adb"), FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("vendor/platform-tools/adb")
    }

    var selected: DeviceProfile? { devices.first { $0.serial == selectedSerial } }

    var visibleCatalogEntries: [CatalogEntry] {
        guard let device = selected, let catalog, let snapshot else { return [] }
        return catalog.entries(for: device, installed: snapshot.installedNames)
    }

    var removedCatalogEntries: [CatalogEntry] {
        guard let device = selected, let catalog, let snapshot else { return [] }
        let removed = Set(snapshot.packages.filter { $0.state == .removedForUser }.map(\.name))
        return catalog.entries(for: device, installed: removed)   // the parameter is just a presence filter
    }

    // MARK: - errors

    func advice(for error: Error) -> String {
        switch error {
        case let e as ADBError: e.advice
        case let e as GitHubError: e.advice
        case let e as SDBError: e.advice
        case let e as TizenError: e.advice
        case let e as SamsungToolsError: e.advice
        case let e as ChangeError:
            switch e {
            case .wrongDevice: "That restore point belongs to a different device."
            case .busy: "Another change is still running on this device. Wait for it to finish."
            default: "Nothing to do."
            }
        case let e as RestoreError: "Couldn't save a restore point first, so nothing was changed. \(e)"
        case let e as DeviceError: e == .invalidHost ? "That address doesn't look right." : "Pairing codes are six digits."
        default: error.localizedDescription
        }
    }

    /// One job at a time: a second request while busy is dropped (the buttons are disabled anyway).
    func run(_ title: String = "Something went wrong", _ work: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do { try await work() }
        catch is CancellationError {}
        catch { alert = AppAlert(title: title, message: advice(for: error)) }
    }

    // MARK: - devices

    func pollDevices() async {
        guard let found = try? await deviceManager.devices() else { return }
        if found != devices {
            devices = found
            if selected == nil && selectedTizen == nil { selectedSerial = found.first?.serial }
            try? await reload()
        }
    }

    func select(_ serial: String) async {
        guard !isBusy else { return }
        selectedSerial = serial
        await run("Couldn't read the device") { try await reload() }
    }

    func reload() async throws {
        guard let device = selected else { snapshot = nil; restorePoints = []; thirdPartyApps = []; return }
        do {
            snapshot = try await DeviceSnapshot.capture(adb: adb, serial: device.serial)
            catalog = try catalogStore.load()
            restorePoints = try await store.list().filter { $0.profile.deviceID == device.deviceID }
            let third = try await adb.run(["shell", "pm", "list", "packages", "-3", "--user", "0"], serial: device.serial)
            thirdPartyApps = Parsers.packages(all: third, installed: third, disabled: "").map(\.name)
        } catch {
            snapshot = nil   // don't leave a stale picture of a device we can no longer read
            throw error
        }
    }

    func connect(host: String, port: Int) async throws {
        try await deviceManager.connect(host: host, port: port)
        await pollDevices()
    }

    func pair(host: String, port: Int, code: String) async throws {
        try await deviceManager.pair(host: host, port: port, code: code)
    }

    func disconnect() async {
        guard let device = selected else { return }
        await run { try await deviceManager.disconnect(serial: device.serial); devices.removeAll { $0.serial == device.serial }; selectedSerial = devices.first?.serial; try await reload() }
    }

    // MARK: - changes

    /// Applies through the engine. Bulk operations show the report sheet; small ones show an undo toast unless something failed.
    func apply(_ changes: [Change], reason: String, showReport: Bool = false) async {
        guard let device = selected else { return }
        await run("Couldn't apply the change") {
            let report = try await engine.apply(changes, on: device, reason: reason)
            present(report, title: reason, showReport: showReport)   // before reload: if the device just dropped, the report is all the user has
            try? await reload()
        }
    }

    func revert(_ rp: RestorePoint, addressChangeConfirmed: Bool = false) async {
        guard let device = selected else { return }
        if rp.profile.serial != device.serial && !addressChangeConfirmed {
            addressChangeRevert = rp
            return
        }
        await run("Couldn't revert") {
            let report = try await engine.revert(rp, on: device)
            present(report, title: "Reverted: \(rp.reason)", showReport: true)
            try? await reload()
        }
    }

    private func present(_ report: ChangeReport, title: String, showReport: Bool) {
        if showReport || report.failed != nil || !report.verified {
            reportToShow = ReportBox(title: title, report: report)
        } else {
            toast = Toast(message: title, undo: report.restorePoint)
        }
    }

    func createRestorePoint() async {
        guard let device = selected else { return }
        await run("Couldn't create a restore point") {
            _ = try await store.create(device: device, reason: "Manual snapshot", pullAPKsFor: [])
            try await reload()
        }
    }

    func deleteRestorePoint(_ rp: RestorePoint) async {
        await run("Couldn't delete") { try await store.delete(rp.id); try await reload() }
    }

    func revealRestorePoint(_ rp: RestorePoint) {
        NSWorkspace.shared.activateFileViewerSelecting([supportDir.appendingPathComponent("RestorePoints").appendingPathComponent(rp.id.uuidString)])
    }

    // MARK: - apps

    func install(apk: URL) async {
        guard let device = selected else { return }
        await run("Couldn't install") {
            try await installer.install(apk: apk, on: device)
            try await reload()
            toast = Toast(message: "Installed \(apk.lastPathComponent)", undo: nil)
        }
    }

    func install(repo: String) async {
        guard let device = selected else { return }
        await run("Couldn't install") {
            let asset = try await installer.installLatest(of: repo, on: device) { [self] options in await choose(options) }
            try await reload()
            toast = Toast(message: "Installed \(asset.name)", undo: nil)
        }
    }

    /// Suspends until the user picks one of several equally good release assets (nil = cancelled).
    func choose(_ options: [ReleaseAsset]) async -> ReleaseAsset? {
        await withCheckedContinuation { continuation in pendingChoice = ChoiceRequest(options: options, continuation: continuation) }
    }

    func setLauncher(_ package: PackageName) async {
        guard let device = selected else { return }
        var component: String?
        await run("Couldn't set the launcher") {
            let out = try await adb.run(["shell", "cmd", "package", "resolve-activity", "--brief", "-a", "android.intent.action.MAIN",
                                         "-c", "android.intent.category.HOME", "-p", package.value], serial: device.serial)
            component = out.split(whereSeparator: \.isNewline).last(where: { $0.contains("/") }).map(String.init)
            if component == nil { alert = AppAlert(title: "Not a launcher", message: "\(package.value) doesn't offer a home screen.") }
        }
        guard let component else { return }
        await apply([.setHome(component)], reason: "Default launcher: \(package.value)")
    }

    // MARK: - console

    func console(_ command: String, confirmed: Bool) async throws -> String {
        guard let device = selected else { return "" }
        return try await Console.run(command, on: device, adb: adb, log: log, confirmed: confirmed)
    }
}
