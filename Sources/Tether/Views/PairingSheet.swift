import AppKit
import SwiftUI
import TetherCore

struct PairingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Kind: String, CaseIterable, Identifiable {
        case fireTV = "Fire TV", androidTV = "Android / Google TV", phone = "Phone or tablet", samsungTV = "Samsung TV"
        var id: String { rawValue }
        var steps: [String] {
            switch self {
            case .fireTV: [
                "Settings → My Fire TV → About, then click your device name seven times to unlock Developer Options.",
                "Settings → My Fire TV → Developer Options → turn ADB debugging on (and Install unknown apps if you want to sideload).",
                "Settings → My Fire TV → About → Network shows the IP address.",
                "Enter it below, then approve “Allow USB debugging?” on the TV (tick Always allow)."]
            case .androidTV: [
                "Settings → System → About, then click Build seven times.",
                "Settings → System → Developer options → turn on USB debugging (and Wireless debugging if offered).",
                "Settings → Network shows the IP address.",
                "Enter it below, then approve the debugging prompt on the TV."]
            case .samsungTV: [
                "On the TV open Apps, then press 1 2 3 4 5 on the remote. Turn Developer mode on.",
                "Enter this Mac's IP address in the Host PC IP field (shown below), then restart the TV.",
                "Come back here, enter the TV's IP address and press Connect. Port 26101 is the default.",
                "Tether sets up Samsung's tools the first time you use a TV. Models from 2019 onwards are supported."]
            case .phone: [
                "Settings → About phone, then tap Build number seven times.",
                "Settings → Developer options → Wireless debugging → on.",
                "Tap “Pair device with pairing code”: it shows an IP:port and a six-digit code. Enter them below and press Pair.",
                "Then connect to the IP and port shown on the main Wireless debugging screen."]
            }
        }
    }

    @State private var kind: Kind = .fireTV
    @State private var host = ""
    @State private var port = "5555"
    @State private var code = ""
    @State private var pairing = false
    @State private var found: [DiscoveredEndpoint] = []
    @State private var message: String?
    @State private var success: String?
    @State private var working = false
    @State private var showSteps = true
    @State private var checkResult: PortChecker.Result?
    @State private var checkTask: Task<Void, Never>?
    @State private var checkID = UUID()
    @State private var discoveryID = UUID()
    @State private var copied = false

    private var endpoint: ConnectionEndpoint? { try? ConnectionEndpoint(address: host, port: port) }
    private var validCode: Bool { code.count == 6 && code.allSatisfy { $0.isASCII && $0.isNumber } }
    private var checking: Bool { checkTask != nil }
    private var canSubmit: Bool {
        endpoint != nil && !working && !checking && model.canManageConnections && (!pairing || validCode)
            && (kind != .samsungTV || model.tizenToolsReady)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add a device").font(.title2.weight(.semibold))
                Text("Keep your Mac and device on the same network.").foregroundStyle(.secondary)
                Picker("Device type", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu).frame(maxWidth: 340, alignment: .leading)
                .disabled(working)
            }
            .padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    setup
                    connectionForm
                    if kind != .samsungTV { nearbyDevices }
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack(spacing: 12) {
                Button("Diagnostics…") {
                    model.openDiagnostics(service: kind == .samsungTV ? .sdb : .adb, endpoint: endpoint)
                }.disabled(working || !model.canManageConnections)
                if working {
                    ProgressView().controlSize(.small)
                    Text(pairing ? "Pairing…" : "Connecting…").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(pairing ? "Pair device" : "Connect") { submit() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 620, height: 620)
        .sheet(isPresented: Bindable(model).showTizenSetup) { TizenSetupSheet() }
        .sheet(isPresented: Bindable(model).showDiagnostics) { DiagnosticsSheet() }
        .onChange(of: kind) {
            pairing = kind == .phone
            port = kind == .samsungTV ? "26101" : kind == .phone ? "" : "5555"
            code = ""
            message = nil
            success = nil
            invalidateCheck()
        }
        .onChange(of: host) {
            invalidateCheck()
            message = nil
            if host.contains(":"), let endpoint {
                host = endpoint.host
                port = String(endpoint.port)
            }
        }
        .onChange(of: port) { invalidateCheck(); message = nil }
        .onChange(of: pairing) { invalidateCheck(); message = nil; code = "" }
        .onDisappear { invalidateCheck() }
        .task(id: discoveryID) {
            for await endpoint in Discovery.stream() {
                guard !Task.isCancelled else { break }
                if !found.contains(endpoint) { found.append(endpoint) }
            }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            DisclosureGroup("Prepare your \(kind.rawValue)", isExpanded: $showSteps) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(kind.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(i + 1)").font(.callout.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary).frame(width: 16)
                            Text(step).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(.callout).padding(.top, 12)
            }
            if kind == .samsungTV {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This Mac’s IP address").font(.caption).foregroundStyle(.secondary)
                        Text(LocalNetwork.address ?? "No Wi-Fi or Ethernet address found")
                            .font(.body.monospaced()).textSelection(.enabled)
                    }
                    Spacer()
                    if let address = LocalNetwork.address {
                        Button(copied ? "Copied" : "Copy IP", systemImage: copied ? "checkmark" : "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(address, forType: .string)
                            copied = true
                        }
                    }
                }
                if !model.tizenToolsReady {
                    HStack {
                        Text("Samsung tools are needed to connect.").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Set up tools…") { model.showTizenSetup = true }
                    }
                }
            }
        }
    }

    private var connectionForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(pairing ? "Pair" : "Connect") manually").font(.headline)
            if kind == .phone || kind == .androidTV {
                Picker("Connection mode", selection: $pairing) {
                    Text("Connect").tag(false)
                    Text("Pair with code").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 320)
                .disabled(working)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device IP address or hostname").font(.callout)
                    TextField("192.168.1.100 or IP:port", text: $host)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("Device IP address or hostname")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(pairing ? "Pairing port" : "Port").font(.callout)
                    TextField("1–65535", text: $port).textFieldStyle(.roundedBorder)
                        .accessibilityLabel(pairing ? "Pairing port" : "Port")
                }.frame(width: 112)
            }
            .disabled(working)
            if !host.isEmpty && endpoint == nil {
                Label("Enter a hostname or IPv4 address and a port from 1 to 65535.", systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.orange)
            }
            if pairing {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Six-digit pairing code").font(.callout)
                    TextField("Code shown on your device", text: $code)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                        .accessibilityLabel("Six-digit pairing code").disabled(working)
                    Text("Use the port from “Pair device with pairing code”. After pairing, switch to Connect and use the main Wireless debugging port.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else if kind == .phone {
                Text("Use the port on the main Wireless debugging screen. It differs from the pairing port.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button(checking ? "Cancel check" : "Check port", systemImage: "network") {
                    if checking { invalidateCheck() } else { checkPort() }
                }
                .disabled(endpoint == nil || working)
                if checking {
                    ProgressView().controlSize(.small)
                    Text("Checking TCP reachability…").font(.callout).foregroundStyle(.secondary)
                }
            }
            if let checkResult { diagnostic(checkResult) }
            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.callout).textSelection(.enabled)
            }
            if let success {
                Label(success, systemImage: "checkmark.circle").foregroundStyle(.green).font(.callout)
            }
        }
    }

    private var nearbyDevices: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nearby Android devices").font(.headline)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { found = []; discoveryID = UUID() }
                    .disabled(working)
            }
            if found.isEmpty {
                Text("Listening for wireless debugging. You can always enter an address manually; Fire TV and Samsung TV may not appear here.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(found, id: \.self) { endpoint in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(endpoint.name).lineLimit(1).truncationMode(.middle)
                        Text("\(endpoint.host):\(endpoint.port) · \(endpoint.kind == .pairing ? "Pairing" : "Connection")")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Use address") {
                        pairing = endpoint.kind == .pairing
                        host = endpoint.host
                        port = String(endpoint.port)
                        code = ""
                    }.disabled(working)
                }
            }
        }
    }

    private func diagnostic(_ result: PortChecker.Result) -> some View {
        let title: String
        let detail: String
        let symbol: String
        switch result {
        case .open:
            title = "Port open"
            detail = "TCP connection succeeded. Debugging must still be enabled and authorised on the device."
            symbol = "checkmark.circle"
        case .refused:
            title = "Connection refused"
            detail = "The address responded, but this port rejected the connection. Check the port and enable debugging on the device."
            symbol = "xmark.circle"
        case .timedOut:
            title = "Port check timed out"
            detail = "Check the address, wake the device, and use the same network. A firewall, VPN or guest Wi-Fi may block access."
            symbol = "clock"
        case .unreachable(let reason):
            title = "Couldn’t reach this port"
            detail = "Check the address and network connection. \(reason)"
            symbol = "wifi.exclamationmark"
        case .cancelled:
            title = "Check cancelled"
            detail = "You can check again when you’re ready."
            symbol = "minus.circle"
        }
        return VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.callout.weight(.semibold))
                .foregroundStyle(result == .open ? Color.green : Color.orange)
            Text(detail).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func invalidateCheck() {
        checkID = UUID()
        checkTask?.cancel()
        checkTask = nil
        checkResult = nil
    }

    private func checkPort() {
        guard let endpoint else { return }
        invalidateCheck()
        let id = checkID
        checkTask = Task {
            let result = await PortChecker.check(endpoint)
            guard !Task.isCancelled, id == checkID else { return }
            checkResult = result
            checkTask = nil
        }
    }

    private func submit() {
        guard canSubmit, let endpoint else { return }
        working = true
        message = nil
        success = nil
        let isPairing = pairing
        Task {
            defer { working = false }
            do {
                if isPairing {
                    try await model.pair(host: endpoint.host, port: endpoint.port, code: code)
                    host = endpoint.host
                    pairing = false
                    code = ""
                    port = ""
                    success = "Paired. Enter the connection port from the main Wireless debugging screen, then connect."
                } else {
                    if kind == .samsungTV { try await model.connectTizen(host: endpoint.host, port: endpoint.port) }
                    else { try await model.connect(host: endpoint.host, port: endpoint.port) }
                    dismiss()
                }
            } catch { message = model.advice(for: error) }
        }
    }
}
