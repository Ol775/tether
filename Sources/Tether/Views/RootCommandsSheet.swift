import AppKit
import SwiftUI
import TetherCore

struct RootCommandsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Experimental root commands").font(.title2.weight(.semibold))
                Text("\(model.selectedTizen?.model ?? "Samsung TV") · \(model.selectedTizen?.serial ?? "Not connected")")
                    .font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Exact model and firmware compatibility is unverified", systemImage: "exclamationmark.triangle")
                            .font(.headline).foregroundStyle(.orange)
                        Text("This uses the third-party archive-root exploit route. It runs one command in a temporary root session. It does not enable Samsung’s normal SDB shell or provide an interactive terminal.")
                        Text("Root commands bypass Tether’s restore-point engine and can damage the TV or its data. Even “Verify root identity” attempts exploitation; it is not a passive diagnostic.")
                    }.font(.callout).fixedSize(horizontal: false, vertical: true)
                    setup
                    Divider()
                    commandForm
                    if let message = model.rootMessage {
                        Text(message).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    if let result = model.rootResult { output(result) }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if model.rootOperationRunning {
                    ProgressView().controlSize(.small)
                    Text("Root attempt in progress…").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.isBusy)
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 700, height: 740)
        .interactiveDismissDisabled(model.isBusy)
        .onChange(of: model.rootToolPath) { model.rootLocalReport = nil }
        .onChange(of: model.rootPayloadPath) { model.rootLocalReport = nil }
        .sheet(item: $model.pendingRootRequest) { request in
            RootCommandConfirmation(request: request)
        }
    }

    private var setup: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 12) {
            Text("Local tool setup").font(.headline)
            Text("Select samsung-tv-root v0.0.12 from its release archive or a prepared source installation. Tether does not download or build exploit payloads.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            pathField("Root tool executable", text: $model.rootToolPath, directory: false)
            pathField("Payload folder (optional override)", text: $model.rootPayloadPath, directory: true)
            HStack {
                Button("Check local setup") { Task { await model.checkRootTool() } }
                    .disabled(!model.canManageConnections || model.rootToolPath.isEmpty)
                Link("Project setup instructions", destination: SamsungRootTool.setupURL)
            }
            Text("Check local setup runs only the selected tool’s version and doctor commands on this Mac. Use a copy you trust.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let report = model.rootLocalReport {
                DisclosureGroup("Local setup report") {
                    Text(report).font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
            }
        }
    }

    private var commandForm: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 12) {
            Text("One-shot command").font(.headline)
            Picker("TV .NET runtime", selection: $model.rootRuntime) {
                ForEach(SamsungRootRuntime.allCases) { Text($0.rawValue).tag($0) }
            }.disabled(!model.canManageConnections)
            TextField("This Mac’s callback IPv4 address", text: $model.rootCallbackAddress)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Root session callback IPv4 address")
                .disabled(!model.canManageConnections)
            Text("The TV must be able to connect back to this Mac. Runtime selection does not prove compatibility.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $model.rootCommand).font(.body.monospaced()).frame(height: 84)
                .scrollContentBackground(.hidden).padding(8)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
                .accessibilityLabel("Root command to run on the TV").disabled(!model.canManageConnections)
            HStack(spacing: 12) {
                Button("Verify root identity…") { model.prepareRootCommand("id") }
                Button("Run command as root…") { model.prepareRootCommand(model.rootCommand) }
            }.disabled(!model.canManageConnections || model.rootToolPath.isEmpty || model.selectedTizen == nil)
            Text("Each button asks for confirmation. Every run acquires a new session; working directory and environment changes do not carry over between commands.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pathField(_ title: String, text: Binding<String>, directory: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout)
            HStack {
                TextField(directory ? "Use the tool’s default payloads" : "/path/to/samsung-tv-root", text: text)
                    .textFieldStyle(.roundedBorder).accessibilityLabel(title)
                Button("Browse…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = directory; panel.canChooseFiles = !directory
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url { text.wrappedValue = url.path; model.rootLocalReport = nil }
                }.accessibilityLabel("Browse for \(title.lowercased())")
            }.disabled(!model.canManageConnections)
        }
    }

    private func output(_ result: SamsungRootResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Last session: authenticated UID 0 · ended", systemImage: "checkmark.shield")
                .font(.headline)
            Text("Exit code: \(result.exitCode.map(String.init) ?? "not reported")\(result.timedOut ? " · command timed out" : "")")
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Text("$ \(result.command)\n\(result.stdout)\(result.stderr.isEmpty ? "" : "\nStderr:\n" + result.stderr)")
                .font(.callout.monospaced()).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("The external tool reported its checked system files unchanged and staging cleaned. This is not an undo of command effects.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct RootCommandConfirmation: View {
    let request: SamsungRootRequest
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Attempt root and run this command?", systemImage: "exclamationmark.triangle")
                .font(.title3.weight(.semibold))
            Text("\(request.deviceModel) · \(request.deviceSerial)")
                .font(.callout.monospaced()).textSelection(.enabled)
            Text("This executes a privilege-escalation exploit with an external tool. Compatibility with this exact TV and firmware is unverified. It can damage the TV or its data. There is no automatic backup or undo; command changes may persist after the session ends.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("Exact command").font(.headline)
            ScrollView {
                Text(request.command).font(.body.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }.frame(minHeight: 100, maxHeight: 180)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
            Text("Tool: \(request.tool.path)\nMac callback: \(request.callback)")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Spacer()
                Button("Cancel") { model.pendingRootRequest = nil }.keyboardShortcut(.cancelAction)
                Button("Attempt root and run", role: .destructive) { model.executeRootCommand(request) }
            }
        }.padding(24).frame(width: 600)
    }
}
