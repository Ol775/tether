import SwiftUI
import TetherCore

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let device = model.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.model).font(.largeTitle.weight(.semibold))
                            Text("\(device.platform == .fireOS ? "Fire OS" : "Android") \(device.androidVersion) · \(device.vendor.capitalized)")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Disconnect") { Task { await model.disconnect() } }.buttonStyle(.glass)
                    }

                    HStack(spacing: 14) {
                        Stat(value: installed, label: "apps installed", symbol: "square.grid.2x2")
                        Stat(value: removed, label: "removed for you", symbol: "trash.slash")
                        Stat(value: model.restorePoints.count, label: "restore points", symbol: "clock.arrow.circlepath")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        row("Address", device.serial)
                        row("API level", String(device.sdk))
                        row("CPU", device.abis.joined(separator: ", "))
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))

                    HStack {
                        Button("Create restore point now", systemImage: "camera.metering.center.weighted") { Task { await model.createRestorePoint() } }
                            .buttonStyle(.glass)
                        Text("Every change also saves one automatically.").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(28)
            }
        }
    }

    private var installed: Int { model.snapshot?.packages.filter { $0.state != .removedForUser }.count ?? 0 }
    private var removed: Int { model.snapshot?.packages.filter { $0.state == .removedForUser }.count ?? 0 }

    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary).frame(width: 90, alignment: .leading); Text(value).textSelection(.enabled) }
    }
}

private struct Stat: View {
    let value: Int
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.tint)
            Text("\(value)").font(.title.weight(.semibold)).contentTransition(.numericText()).animation(Theme.smooth, value: value)
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
