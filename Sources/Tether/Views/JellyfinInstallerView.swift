import SwiftUI
import TetherCore

struct JellyfinInstallerView: View {
    @Environment(AppModel.self) private var model
    @State private var checking = false
    @State private var error: String?
    @State private var installedAndroid: Bool?
    @State private var installedVersion: String?
    @State private var latestVersion: String?
    @State private var revision: String?
    @State private var webVersion = ""
    @State private var profile = ""
    @State private var confirmingBuild = false
    @State private var lastChecked: Date?

    private var samsung: Bool { model.selectedTizen != nil }
    private var deviceKey: String { model.selectedTizen?.serial ?? model.selected?.serial ?? "" }
    private var installed: Bool { samsung ? model.tizenApps.contains { $0.id == Jellyfin.tizenID } : installedAndroid == true }
    private var saved: JellyfinBuild? { model.jellyfinCache.flatMap { Jellyfin.savedBuild(in: $0) } }
    private var disabled: Bool { checking || model.isBusy }
    private var androidUpToDate: Bool {
        guard let latestVersion, let installedVersion,
              let latest = Jellyfin.stableVersion(latestVersion), let current = Jellyfin.stableVersion(installedVersion) else { return false }
        return !Updater.isNewer(latest, than: current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "play.rectangle.on.rectangle").font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Jellyfin").font(.title3.weight(.semibold))
                    Text(samsung ? "Build and sign the official Samsung TV client." : "Official Jellyfin for Fire TV and Android TV.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if installed { Label("Installed", systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary) }
            }
            if samsung { samsungOptions } else { androidOptions }
            if let latestVersion {
                Text("Latest \(samsung ? "Jellyfin Web" : "Android TV release"): \(latestVersion)\(revision.map { " · Tizen source " + $0.prefix(8) } ?? "")")
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let lastChecked { Text("Checked \(lastChecked.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            if let error { Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if let progress = model.jellyfinProgress {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(progress).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if model.jellyfinCanCancel { Button("Cancel") { model.jellyfinOperation?.cancel() } }
                }
            }
            HStack(spacing: 12) {
                Button(checking ? "Checking…" : "Check for updates", systemImage: "arrow.clockwise") { Task { await checkUpdates() } }
                    .disabled(disabled)
                if samsung {
                    Button(installed ? "Build and update…" : "Build and install…") { confirmingBuild = true }
                        .buttonStyle(.glassProminent)
                        .disabled(disabled || Jellyfin.stableVersion(webVersion) == nil || profile.trimmingCharacters(in: .whitespaces).isEmpty || !model.tizenToolsReady)
                    if installed {
                        Button("Reinstall saved build") { model.startJellyfinTizen(version: "", profile: "", revision: nil, reinstall: true) }
                            .disabled(disabled || saved == nil)
                    }
                } else {
                    Button(installed ? "Update Jellyfin" : "Install Jellyfin") { model.startJellyfinAndroid() }
                        .buttonStyle(.glassProminent).disabled(disabled || (installed && androidUpToDate))
                    if installed { Button("Reinstall latest") { model.startJellyfinAndroid() }.disabled(disabled) }
                }
            }
            HStack(spacing: 16) {
                Link("Official project", destination: URL(string: samsung ? "https://github.com/jellyfin/jellyfin-tizen" : "https://github.com/jellyfin/jellyfin-androidtv")!)
                if !samsung { Link("Fire TV / ADB guide", destination: URL(string: "https://gist.github.com/nielsvanvelzen/96fd588194729d6845f2d5e414cffb8d")!) }
            }.font(.callout)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
        .task(id: deviceKey) {
            error = nil; latestVersion = nil; revision = nil; installedVersion = nil; installedAndroid = nil; lastChecked = nil
            webVersion = saved?.webVersion ?? ""; profile = saved?.profile ?? ""
            if !samsung { await readAndroidStatus() }
        }
        .onChange(of: model.isBusy) { if !model.isBusy && !samsung { Task { await readAndroidStatus() } } }
        .confirmationDialog("Build and install Jellyfin?", isPresented: $confirmingBuild, titleVisibility: .visible) {
            Button("Build, sign and install") {
                model.startJellyfinTizen(version: webVersion, profile: profile.trimmingCharacters(in: .whitespacesAndNewlines), revision: revision, reinstall: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tether downloads official Jellyfin source and npm dependencies, runs their build scripts on this Mac, signs Web \(webVersion) with \(profile), and installs it on \(model.selectedTizen?.model ?? "the TV"). This can take several minutes. It does not uninstall the existing app.")
        }
    }

    private var samsungOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let saved {
                Text("Last installed by Tether: Web \(saved.webVersion) · Tizen \(saved.tizenCommit.prefix(8))")
                    .font(.callout).foregroundStyle(.secondary)
            } else if installed {
                Text("This TV has Jellyfin; its build version is unknown to Tether.").font(.callout).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Jellyfin Web version").font(.callout)
                    TextField("Match your server, e.g. 10.10.7", text: $webVersion).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Jellyfin Web version")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Samsung certificate profile").font(.callout)
                    TextField("Profile name from Certificate Manager", text: $profile).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Active Samsung certificate profile")
                }
            }.disabled(disabled)
            Text("Requires Git, Node.js 20+, npm and Tizen Studio. Set the named certificate profile active in Certificate Manager and include this TV. Choose the Web version matching your server; the latest may differ.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Updates install over Jellyfin. Reinstall re-applies the saved signed build; firmware may reject same-version installs. Tether never uninstalls it automatically.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var androidOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let installedVersion {
                Text("Installed version: \(installedVersion)\(androidUpToDate ? " · Up to date" : "")").font(.callout).foregroundStyle(.secondary)
            }
            Text("Downloads the stable release APK from Jellyfin’s GitHub, verifies its size and SHA-256, and installs it with ADB. Update and reinstall keep app data; no uninstall or reset is sent. A different signing key is reported as an error.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func readAndroidStatus() async {
        guard let device = model.selected else { return }
        do {
            let output = try await model.adb.run(["shell", "pm", "list", "packages", Jellyfin.androidID.value], serial: device.serial)
            guard model.selected?.serial == device.serial else { return }
            installedAndroid = output.split(whereSeparator: \.isNewline).contains("package:\(Jellyfin.androidID.value)")
            if installedAndroid == true {
                let dump = try? await model.adb.run(["shell", "dumpsys", "package", Jellyfin.androidID.value], serial: device.serial)
                guard model.selected?.serial == device.serial else { return }
                installedVersion = dump.flatMap(Jellyfin.installedAndroidVersion)
            }
        } catch { self.error = model.advice(for: error) }
    }

    private func checkUpdates() async {
        guard !disabled else { return }
        checking = true; error = nil
        let key = deviceKey
        defer { checking = false }
        do {
            if samsung {
                async let release = GitHubRelease.latest(owner: "jellyfin", repo: "jellyfin-web")
                async let sha = Jellyfin.tizenRevision()
                let (web, commit) = try await (release, sha)
                guard key == deviceKey else { return }
                latestVersion = web.tag; revision = commit
                if webVersion.isEmpty { webVersion = Jellyfin.stableVersion(web.tag) ?? "" }
            } else {
                let release = try await GitHubRelease.latest(owner: "jellyfin", repo: "jellyfin-androidtv")
                _ = try Jellyfin.androidAsset(release, abis: model.selected?.abis ?? [])
                guard key == deviceKey else { return }
                latestVersion = release.tag
                await readAndroidStatus()
            }
            lastChecked = .now
        } catch { self.error = model.advice(for: error) }
    }
}
