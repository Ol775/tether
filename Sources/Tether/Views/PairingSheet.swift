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
    @State private var found: [DiscoveredEndpoint] = []
    @State private var message: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a device").font(.title2.weight(.semibold))
            Picker("Device type", selection: $kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden()

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(kind.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1)").font(.callout.monospacedDigit().weight(.semibold)).foregroundStyle(.tint).frame(width: 16)
                        Text(step)
                    }
                }
            }
            .font(.callout)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
            .animation(Theme.smooth, value: kind)
            .onChange(of: kind) { port = kind == .samsungTV ? "26101" : "5555" }

            if kind == .samsungTV {
                HStack {
                    Text("This Mac's IP address:").foregroundStyle(.secondary)
                    Text(LocalNetwork.address ?? "not on a network").textSelection(.enabled).fontWeight(.medium)
                    Spacer()
                    if !model.tizenToolsReady {
                        Button("Set up Samsung tools…") { model.showTizenSetup = true }.buttonStyle(.glass)
                    }
                }
                .font(.callout)
            }

            if !found.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Found on your network").font(.headline)
                    ForEach(found, id: \.self) { endpoint in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(endpoint.name)
                                Text("\(endpoint.host):\(endpoint.port) · \(endpoint.kind == .pairing ? "ready to pair" : "ready to connect")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if endpoint.kind == .pairing {
                                Button("Pair") { go { try await model.pair(host: endpoint.host, port: endpoint.port, code: code) } }
                                    .disabled(code.count != 6)
                            } else {
                                Button("Connect") { go { try await model.connect(host: endpoint.host, port: endpoint.port) } }
                            }
                        }
                    }
                    if found.contains(where: { $0.kind == .pairing }) {
                        TextField("Six-digit pairing code", text: $code).frame(width: 220)
                    }
                }
            }

            HStack {
                TextField("IP address", text: $host).textFieldStyle(.roundedBorder)
                TextField("Port", text: $port).textFieldStyle(.roundedBorder).frame(width: 80)
                Button("Connect") {
                    let host = host.trimmingCharacters(in: .whitespaces)
                    if kind == .samsungTV { go { try await model.connectTizen(host: host, port: Int(port) ?? 26101) } }
                    else { go { try await model.connect(host: host, port: Int(port) ?? 5555) } }
                }
                .buttonStyle(.glassProminent)
                .disabled(host.isEmpty || working || (kind == .samsungTV && !model.tizenToolsReady))
            }

            if let message {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
            }
            HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24).frame(width: 560)
        // Presented from here: SwiftUI shows one sheet at a time, so a second sheet from the root view would never appear over this one.
        .sheet(isPresented: Bindable(model).showTizenSetup) { TizenSetupSheet() }
        .task { for await endpoint in Discovery.stream() where !found.contains(endpoint) { found.append(endpoint) } }
    }

    private func go(_ work: @escaping () async throws -> Void) {
        working = true
        message = nil
        Task {
            defer { working = false }
            do { try await work(); if model.selected != nil || model.selectedTizen != nil { dismiss() } }
            catch { message = model.advice(for: error) }
        }
    }
}
