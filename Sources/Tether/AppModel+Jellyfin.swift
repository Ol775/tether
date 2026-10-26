import Foundation
import TetherCore

extension AppModel {
    var jellyfinCache: URL? {
        guard let id = selectedTizen?.deviceID ?? selected?.deviceID else { return nil }
        return Jellyfin.cacheFolder(root: supportDir, deviceID: id)
    }

    func startJellyfinAndroid() {
        guard let device = selected, canManageConnections else { return }
        beginJellyfin()
        jellyfinOperation = Task { [self] in
            defer { endJellyfin() }
            let download = FileManager.default.temporaryDirectory.appendingPathComponent("tether-jellyfin-apk-\(UUID())")
            defer { try? FileManager.default.removeItem(at: download) }
            do {
                jellyfinProgress = "Checking the official Jellyfin Android TV release…"
                let release = try await GitHubRelease.latest(owner: "jellyfin", repo: "jellyfin-androidtv")
                let asset = try Jellyfin.androidAsset(release, abis: device.abis)
                jellyfinProgress = "Downloading and verifying \(release.tag)…"
                let apk = try await installer.download(asset, into: download)
                let packages = try await adb.run(["shell", "pm", "list", "packages", Jellyfin.androidID.value], serial: device.serial)
                let installed = packages.split(whereSeparator: \.isNewline).contains("package:\(Jellyfin.androidID.value)")
                jellyfinProgress = "Saving a restore point…"
                let rp = try await store.create(device: device, reason: "Jellyfin \(release.tag)", pullAPKsFor: installed ? [Jellyfin.androidID] : [])
                await log.append("\(device.serial): restore point \(rp.id) before Jellyfin \(release.tag)")
                try Task.checkCancellation()
                jellyfinCanCancel = false
                jellyfinProgress = "Installing Jellyfin \(release.tag)…"
                // -r installs over the existing app; no uninstall or app-data reset is sent.
                try await installer.install(apk: apk, on: device)
                let paths = try await adb.run(["shell", "pm", "path", Jellyfin.androidID.value], serial: device.serial)
                guard paths.split(whereSeparator: \.isNewline).contains(where: { $0.hasPrefix("package:") }) else { throw JellyfinError.notInstalled }
                if selected?.serial == device.serial { try await reload() }
                toast = Toast(message: "Jellyfin \(release.tag) installed", undo: nil)
            } catch is CancellationError {} catch {
                alert = AppAlert(title: "Couldn't install Jellyfin", message: advice(for: error))
            }
        }
    }

    func startJellyfinTizen(version: String, profile: String, password: String, revision: String?, reinstall: Bool) {
        guard let tv = selectedTizen, let cache = jellyfinCache, canManageConnections else { return }
        beginJellyfin()
        let operationID = jellyfinOperationID
        jellyfinOperation = Task { [self] in
            defer { endJellyfin() }
            do {
                let build: JellyfinBuild
                if reinstall {
                    guard let saved = Jellyfin.savedBuild(in: cache) else { throw JellyfinError.noSavedPackage }
                    build = saved
                } else {
                    guard let cli = tools.tizenCLI else { throw SDBError.toolsMissing }
                    try await certificates.checkProfile(named: profile)
                    guard !password.isEmpty else { throw JellyfinError.buildFailed("Enter your Samsung certificate password to sign the package.") }
                    guard let certs = certificates.activeProfileFiles() else {
                        throw JellyfinError.buildFailed("Couldn't find the active Samsung certificate. Set one up in certificate setup first.")
                    }
                    let author = WidgetSigner.Identity(p12: try Data(contentsOf: certs.author), password: password)
                    let distributor = WidgetSigner.Identity(p12: try Data(contentsOf: certs.distributor), password: password)
                    let commit: String
                    if let revision { commit = revision } else { commit = try await Jellyfin.tizenRevision() }
                    build = try await JellyfinTizenBuilder(cli: cli).build(version: version, commit: commit, profile: profile, cache: cache,
                                                                           author: author, distributor: distributor) { [weak self] message in
                        Task { @MainActor in
                            guard let self, self.jellyfinOperationID == operationID else { return }
                            self.jellyfinProgress = message
                        }
                    }
                }
                try Task.checkCancellation()
                jellyfinCanCancel = false
                jellyfinProgress = "Saving a restore point and installing the signed Jellyfin package…"
                let report = try await tizenEngine.apply([.installSigned(wgt: build.package, expectedApp: Jellyfin.tizenID)], on: tv,
                                                         reason: "Jellyfin Web \(build.webVersion), Tizen \(build.tizenCommit.prefix(8))")
                if let (_, failure) = report.failed { throw failure }
                guard report.verified else { throw JellyfinError.notInstalled }
                try Jellyfin.save(build, in: cache)
                if selectedTizen?.serial == tv.serial { try await reloadTizen() }
                toast = Toast(message: "Jellyfin Web \(build.webVersion) installed", undo: nil)
            } catch is CancellationError {} catch {
                alert = AppAlert(title: "Couldn't install Jellyfin", message: advice(for: error))
            }
        }
    }

    private func beginJellyfin() {
        isBusy = true
        jellyfinCanCancel = true
        jellyfinOperationID = UUID()
        jellyfinProgress = "Preparing Jellyfin…"
    }

    private func endJellyfin() {
        jellyfinOperationID = UUID()
        jellyfinProgress = nil
        jellyfinCanCancel = false
        jellyfinOperation = nil
        isBusy = false
    }
}
