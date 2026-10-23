import SwiftUI
import TetherCore
import UniformTypeIdentifiers

struct TizenAppsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var choosingFile = false
    @State private var dropTargeted = false

    private static let types = ["wgt", "tpk"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Install an app").font(.headline)
                CertificateStatusView()
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.app").font(.title2).foregroundStyle(.secondary)
                    Text("Drop a signed .wgt or .tpk here").foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose file…") { choosingFile = true }.buttonStyle(.glass).disabled(model.isBusy)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).strokeBorder(dropTargeted ? Color.accentColor : .secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                .animation(reduceMotion ? nil : Theme.quick, value: dropTargeted)
                .dropDestination(for: URL.self, action: { urls, _ in
                    guard let file = urls.first(where: { ["wgt", "tpk"].contains($0.pathExtension.lowercased()) }) else { return false }
                    install(file)
                    return true
                }, isTargeted: { dropTargeted = $0 })
                if model.isBusy { ProgressView().controlSize(.small) }

                Text("Packages must be signed with a certificate that includes this TV. Tether keeps a copy of each package it installs, so removing the app later can be undone. To remove an app, use Debloat.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: Self.types.isEmpty ? [.data] : Self.types) { result in
            if case .success(let url) = result { install(url) }
        }
    }

    private func install(_ file: URL) {
        let scoped = file.startAccessingSecurityScopedResource()
        Task {
            defer { if scoped { file.stopAccessingSecurityScopedResource() } }
            await model.applyTizen([.install(wgt: file)], reason: "Installed \(file.lastPathComponent)")
        }
    }
}
