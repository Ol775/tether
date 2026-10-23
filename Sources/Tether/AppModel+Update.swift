import AppKit
import Foundation
import TetherCore

extension AppModel {
    /// The running version, or nil for a bare executable (swift run, demo) that has no bundle to update.
    /// `TETHER_PRETEND_VERSION` only lowers it for testing; it can't make anything install without the release signature.
    static var installedVersion: String? {
        if let pretend = ProcessInfo.processInfo.environment["TETHER_PRETEND_VERSION"], Updater.isPlainVersion(pretend) { return pretend }
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private static var updatesFolder: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Tether")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir
    }

    /// `userInitiated` (the menu item) reports "up to date" and failures; the background check stays quiet.
    func checkForUpdates(userInitiated: Bool = false) async {
        if ProcessInfo.processInfo.environment["TETHER_NO_UPDATE_CHECK"] != nil { return }   // demo/screenshot runs never touch the network
        guard let installed = Self.installedVersion else {
            if userInitiated { alert = AppAlert(title: "Updates", message: "This copy of Tether isn't a packaged app, so it can't update itself.") }
            return
        }
        switch updateStatus { case .checking, .installing: return; default: break }
        Self.removeOldDownloads()
        let before = updateStatus
        updateStatus = .checking
        do {
            if let info = try await Updater.latest(), Updater.isNewer(info.version, than: installed) {
                if case .available(let known) = before, known.version == info.version {} else { updateDismissed = false }
                updateStatus = .available(info)
            } else {
                updateStatus = .idle
                if userInitiated { toast = Toast(message: "Tether is up to date", undo: nil) }
            }
        } catch {
            updateStatus = before == .checking ? .idle : before
            if userInitiated { alert = AppAlert(title: "Couldn't check for updates", message: advice(for: error)) }
        }
    }

    func installUpdate() async {
        guard case .available(let info) = updateStatus else { return }
        guard !isBusy else {
            alert = AppAlert(title: "Finish the current change first", message: "Tether is changing a device. Update once that is done.")
            return
        }
        let dest = Bundle.main.bundleURL
        guard UpdateInstaller.canReplace(dest) else {
            // A translocated or read-only copy can't swap itself: send the user to the release instead.
            alert = AppAlert(title: "Move Tether to Applications to update", message: "This copy can't replace itself. Move Tether to your Applications folder and reopen it, or download the new version from the release page.")
            if let page = info.pageURL { NSWorkspace.shared.open(page) }
            return
        }
        updateStatus = .installing("Starting…")
        do {
            let installer = UpdateInstaller(workDir: Self.updatesFolder)
            let app = try await installer.prepare(info) { line in Task { @MainActor in self.updateStatus = .installing(line) } }
            updateStatus = .installing("Installing…")
            try installer.apply(app, to: dest)
            NSApp.terminate(nil)
        } catch {
            updateStatus = .available(info)
            alert = AppAlert(title: "The update wasn't installed", message: advice(for: error))
        }
    }

    /// Update folders older than a day (a finished update leaves its unpacked app behind until then).
    private static func removeOldDownloads() {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: updatesFolder.path)) ?? [] where name.hasPrefix("update-") {
            let url = updatesFolder.appendingPathComponent(name)
            if let modified = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date, Date().timeIntervalSince(modified) > 86400 { try? fm.removeItem(at: url) }
        }
    }
}
