import SwiftUI
import TetherCore

struct PairingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Kind: String, CaseIterable, Identifiable {
        case fireTV = "Fire TV", androidTV = "Android / Google TV", phone = "Phone or tablet"
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
                Button("Connect") { go { try await model.connect(host: host.trimmingCharacters(in: .whitespaces), port: Int(port) ?? 5555) } }
                    .buttonStyle(.glassProminent)
                    .disabled(host.isEmpty || working)
            }

            if let message {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
            }
            HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24).frame(width: 560)
        .task { for await endpoint in Discovery.stream() where !found.contains(endpoint) { found.append(endpoint) } }
    }

    private func go(_ work: @escaping () async throws -> Void) {
        working = true
        message = nil
        Task {
            defer { working = false }
            do { try await work(); if model.selected != nil { dismiss() } }
            catch { message = model.advice(for: error) }
        }
    }
}
