import SwiftUI
import TetherCore
import UniformTypeIdentifiers

struct AppsView: View {
    @Environment(AppModel.self) private var model
    @State private var repo = ""
    @State private var choosingFile = false
    @State private var dropTargeted = false

    private static let apkType = UTType(filenameExtension: "apk") ?? .data

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                JellyfinInstallerView()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Install an app").font(.headline)
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.app").font(.title2).foregroundStyle(.secondary)
                        Text("Drop an .apk here").foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose file…") { choosingFile = true }.buttonStyle(.glass)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).strokeBorder(dropTargeted ? Color.accentColor : .secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    .animation(Theme.quick, value: dropTargeted)
                    .dropDestination(for: URL.self, action: { urls, _ in
                        guard let apk = urls.first(where: { $0.pathExtension.lowercased() == "apk" }) else { return false }
                        Task { await model.install(apk: apk) }
                        return true
                    }, isTargeted: { dropTargeted = $0 })

                    HStack {
                        TextField("GitHub repository (owner/name or link)", text: $repo).textFieldStyle(.roundedBorder)
                            .onSubmit(installRepo)
                        Button("Install latest release", action: installRepo).buttonStyle(.glassProminent)
                            .disabled(repo.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
                    }
                    if model.isBusy { ProgressView().controlSize(.small) }
                }
                .padding(16).background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Apps you installed").font(.headline)
                    if model.thirdPartyApps.isEmpty {
                        Text("None yet.").foregroundStyle(.secondary)
                    }
                    ForEach(model.thirdPartyApps, id: \.self) { app in
                        HStack {
                            Text(app.value).font(.callout.monospaced()).textSelection(.enabled)
                            Spacer()
                            Menu("Actions") {
                                Button("Set as default launcher") { Task { await model.setLauncher(app) } }
                            }
                            .menuStyle(.button).buttonStyle(.glass).controlSize(.small).fixedSize()
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
            .padding(24)
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [Self.apkType]) { result in
            if case .success(let url) = result { Task { await model.install(apk: url) } }
        }
    }

    private func installRepo() {
        let input = repo.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }
        Task { await model.install(repo: input) }
    }
}
