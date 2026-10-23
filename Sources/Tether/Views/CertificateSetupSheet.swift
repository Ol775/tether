import AppKit
import SwiftUI
import TetherCore
import UniformTypeIdentifiers

struct CertificateStatusView: View {
    @Environment(AppModel.self) private var model
    @State private var showingSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let state = model.certificateState {
                Label(state.advice, systemImage: state == .ready ? "checkmark.seal" : "info.circle")
                    .font(.callout).foregroundStyle(state == .ready ? Color.green : Color.secondary)
            }
            Button("Certificate setup…", systemImage: "person.badge.key") { showingSetup = true }
        }
        .sheet(isPresented: $showingSetup) { CertificateSetupSheet() }
    }
}

struct CertificateSetupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var choosingProfile = false
    @State private var working = false
    @State private var error: String?
    @State private var selectedFile: String?
    @State private var packageManagerProcess: Process?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Samsung TV certificate").font(.title2.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Use a Samsung signing profile that includes this TV. Certificate Manager can create a profile or import your existing .p12 certificates.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("1. Open Certificate Manager and choose Samsung → TV.")
                        Text("2. Create or import your author and distributor certificates. Add this TV from the connected-device list.")
                        Text("3. Save the profile, then return here and refresh its status.")
                    }.font(.callout)
                    HStack {
                        Button("Open Certificate Manager", systemImage: "arrow.up.forward.app") { openManager() }
                            .buttonStyle(.glassProminent).disabled(working || model.tools.certificateManager == nil)
                        Link("Samsung’s certificate guide", destination: URL(string: "https://developer.samsung.com/smarttv/develop/getting-started/setting-up-sdk/creating-certificates.html")!)
                    }
                    if model.tools.certificateManager == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Install Certificate Manager in Tizen Package Manager (Main SDK), plus Samsung Certificate Extension (Extension SDK). Then return here and refresh.")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("Open Package Manager", systemImage: "shippingbox") {
                                error = nil
                                do {
                                    let process = try model.tools.startPackageManager()
                                    packageManagerProcess = process
                                    Task {
                                        try? await Task.sleep(for: .seconds(2))
                                        if !process.isRunning {
                                            error = "Package Manager couldn’t stay open. Install the full Tizen Studio SDK from Samsung’s website, or choose an existing profile below."
                                        }
                                    }
                                } catch { self.error = "Couldn’t open Package Manager: \(error.localizedDescription)" }
                            }.disabled(working)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Already have a signing profile?").font(.headline)
                        Text("Choose its profiles.xml file. Your private keys and passwords stay in Samsung’s certificate files.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Choose existing profile…") { choosingProfile = true }.disabled(working)
                        if let selectedFile { Text("Using \(selectedFile)").font(.callout).foregroundStyle(.secondary) }
                    }
                    Text("Sign your .wgt with this profile in Samsung’s tools before installing it in Tether.")
                        .font(.callout).foregroundStyle(.secondary)
                    if let state = model.certificateState {
                        Label(state.advice, systemImage: state == .ready ? "checkmark.seal" : "info.circle")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                    if let error { Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Refresh status", systemImage: "arrow.clockwise") { refresh() }.disabled(working)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24).frame(width: 580, height: 620)
        .fileImporter(isPresented: $choosingProfile, allowedContentTypes: [.xml]) { result in
            switch result {
            case .success(let file): useProfile(file)
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }

    private func openManager() {
        error = nil
        guard let app = model.tools.certificateManager else {
            error = "Certificate Manager is missing. Install it and Samsung Certificate Extension in Tizen Studio."
            return
        }
        openApplication(app)
    }

    private func openApplication(_ app: URL) {
        NSWorkspace.shared.openApplication(at: app, configuration: .init()) { _, failure in
            if let failure { Task { @MainActor in error = failure.localizedDescription } }
        }
    }

    private func refresh() {
        working = true
        error = nil
        Task { await model.refreshTizenCertificate(); working = false }
    }

    private func useProfile(_ file: URL) {
        working = true
        error = nil
        Task {
            let scoped = file.startAccessingSecurityScopedResource()
            defer { if scoped { file.stopAccessingSecurityScopedResource() }; working = false }
            do {
                try await model.certificates.useProfilesFile(file)
                selectedFile = file.lastPathComponent
                await model.refreshTizenCertificate()
            } catch { self.error = error.localizedDescription }
        }
    }
}
