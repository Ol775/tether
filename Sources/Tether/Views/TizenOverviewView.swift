import SwiftUI
import TetherCore

struct TizenOverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let tv = model.selectedTizen {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tv.model).font(.largeTitle.weight(.semibold))
                            Text("Samsung\(tv.modelYear.map { " · \($0)" } ?? "") · Tizen \(tv.tizenVersion)").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Disconnect") { Task { await model.disconnectTizen() } }.buttonStyle(.glass)
                    }

                    HStack(spacing: 14) {
                        stat(model.tizenApps.count, "apps on the TV", "square.grid.2x2")
                        stat(model.tizenLocked.count, "locked by Samsung", "lock")
                        stat(model.tizenRestorePoints.count, "restore points", "clock.arrow.circlepath")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        row("Address", tv.serial)
                        row("Shell", tv.shellEnabled ? "Enabled" : "Disabled by Samsung")
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))

                    CertificateStatusView()
                    Text("A restore point is saved automatically before every change.").font(.callout).foregroundStyle(.secondary)
                }
                .padding(28)
            }
        }
    }

    private func stat(_ value: Int, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text("\(value)").font(.title.weight(.semibold).monospacedDigit()).contentTransition(.numericText())
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary).frame(width: 90, alignment: .leading); Text(value).textSelection(.enabled) }
    }
}
