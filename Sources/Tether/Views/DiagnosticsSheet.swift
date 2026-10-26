import AppKit
import SwiftUI
import TetherCore

struct DiagnosticsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var restart: DebugService?
    @State private var copied = false

    private var endpoint: ConnectionEndpoint? {
        try? ConnectionEndpoint(address: model.diagnosticAddress, port: model.diagnosticPort)
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Connection diagnostics").font(.title2.weight(.semibold))
                Text("Find where the connection stops, then restart the service if needed.")
                    .foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    targetForm
                    if let progress = model.diagnosticProgress {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(progress).font(.callout)
                        }.accessibilityElement(children: .combine)
                    }
                    if let report = model.diagnosticReport { results(report) }
                    if let message = model.serviceMessage {
                        Text(message).font(.callout).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                    recovery
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack(spacing: 12) {
                Button(copied ? "Copied" : "Copy report", systemImage: "doc.on.doc") {
                    guard let report = model.diagnosticReport else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("Tether \(AppModel.installedVersion ?? "development build")\n" + report.text, forType: .string)
                    copied = true
                }.disabled(model.diagnosticReport == nil)
                Spacer()
                Button("Done") { model.diagnosticTask?.cancel(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.restartingService)
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 660, height: 700)
        .interactiveDismissDisabled(model.restartingService)
        .onChange(of: model.diagnosticService) {
            model.diagnosticPort = model.diagnosticService.defaultPort
            clearReport()
        }
        .onChange(of: model.diagnosticAddress) { clearReport() }
        .onChange(of: model.diagnosticPort) { clearReport() }
        .onChange(of: model.diagnosticReport?.date) { copied = false }
        .onDisappear { model.diagnosticTask?.cancel() }
        .confirmationDialog("Restart \(restart?.rawValue.uppercased() ?? "service")?", isPresented: Binding(get: { restart != nil }, set: { if !$0 { restart = nil } }), titleVisibility: .visible) {
            if let service = restart {
                Button("Restart \(service.rawValue.uppercased())") { restart = nil; Task { await model.restartService(service) } }
            }
            Button("Cancel", role: .cancel) { restart = nil }
        } message: {
            Text(restart == .sdb
                 ? "Samsung’s shared SDB service will briefly disconnect TVs in Tether and other Samsung tools. Tether will try to reconnect its listed TVs and the address above. No TV apps or settings are changed."
                 : "Tether’s ADB service on port 5038 will briefly disconnect Android and Fire TV devices. Tether will try to reconnect its network devices and the address above. The system ADB service on port 5037 is left running.")
        }
    }

    private var targetForm: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 16) {
            Picker("Device service", selection: $model.diagnosticService) {
                ForEach(DebugService.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).disabled(!model.canManageConnections)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device IP address or hostname").font(.callout)
                    TextField("192.168.1.100", text: $model.diagnosticAddress)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("Diagnostic device address")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Debugging port").font(.callout)
                    TextField("1–65535", text: $model.diagnosticPort)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("Diagnostic debugging port")
                }.frame(width: 120)
            }.disabled(!model.canManageConnections)
            if !model.diagnosticAddress.isEmpty && endpoint == nil {
                Label("Enter a valid address and a port from 1 to 65535.", systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                Button("Run diagnostics", systemImage: "stethoscope") { model.startDiagnostics() }
                    .buttonStyle(.glassProminent)
                    .disabled(endpoint == nil || !model.canManageConnections)
                if model.diagnosticTask != nil {
                    Button("Stop checks") { model.diagnosticTask?.cancel() }
                }
            }
            Text("Checks read connection status only. Reports include local IP addresses; review before sharing. Nothing is uploaded.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func results(_ report: ConnectionReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Connection checks").font(.headline)
                Spacer()
                Text(report.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ForEach(report.checks) { check in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: check.status == .passed ? "checkmark.circle" : check.status == .failed ? "xmark.circle" : "exclamationmark.circle")
                        .foregroundStyle(check.status == .passed ? Color.green : Color.orange)
                        .accessibilityLabel(check.status.rawValue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(check.title).font(.callout.weight(.semibold))
                        Text(check.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }.fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Next step").font(.callout.weight(.semibold))
                Text(report.nextStep).font(.callout).textSelection(.enabled)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
        }
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Restart and reconnect").font(.headline)
            Text("Service restarts briefly disconnect devices. App and service restarts are unavailable while an operation or update is running.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Restart SDB…") { restart = .sdb }
                    .disabled(!model.canManageConnections || !model.tizenToolsReady)
                Button("Restart ADB…") { restart = .adb }
                    .disabled(!model.canManageConnections)
                Spacer()
                Button("Restart Tether") { model.restartApplication() }
                    .disabled(!model.canRestartApp)
            }
            if !model.tizenToolsReady {
                Text("Set up Samsung tools in Add a device to enable SDB restart.").font(.caption).foregroundStyle(.secondary)
            }
            if Bundle.main.bundleURL.pathExtension != "app" {
                Text("App restart is available in the packaged Tether.app.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func clearReport() {
        model.diagnosticReport = nil
        model.serviceMessage = nil
        copied = false
    }
}
