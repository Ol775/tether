import SwiftUI
import TetherCore

struct TizenSetupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var accepted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up Samsung tools").font(.title2.weight(.semibold))
            Text("Samsung TVs are managed with Samsung's own command-line tools (sdb and the Tizen CLI). Tether doesn't ship them. With your OK it downloads Samsung's official installer (about 265 MB), checks it against a fixed checksum, and installs it inside Tether's own folder.")
            Link("Tizen Studio install notes and licence", destination: URL(string: "https://docs.tizen.org/application/tizen-studio/setup/install-sdk/")!)
            Toggle("I have read and accept Samsung's Tizen Studio licence", isOn: $accepted)
                .toggleStyle(.checkbox)

            if !model.toolsProgress.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.toolsProgress.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                if model.isBusy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.tizenToolsReady ? "Done" : "Download and install") {
                    if model.tizenToolsReady { dismiss() } else { Task { await model.setUpSamsungTools(acceptingLicense: accepted) } }
                }
                .buttonStyle(.glassProminent)
                .disabled((!accepted && !model.tizenToolsReady) || model.isBusy)
            }
        }
        .padding(24).frame(width: 520)
    }
}
