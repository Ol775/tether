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
                    DisclosureGroup("Samsung system customisation") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SDB root capability: \(tv.rootAvailable ? "reported by firmware" : "unavailable")")
                            Text("Locked preinstalled apps and boot-logo replacement are not supported through the current developer-mode connection.")
                            Text("Third-party root projects depend on the exact model and firmware. A disabled SDB root flag does not establish whether a separate exploit would work.")
                            Button("Experimental root commands…") { model.showRootCommands = true }
                                .disabled(!model.canManageConnections)
                            Link("Root project compatibility and limitations", destination: URL(string: "https://github.com/chris-ritsen/samsung-tv-root#tv-compatibility")!)
                            Link("Untethered fork (boot-time persistence, different firmware tested)", destination: URL(string: "https://github.com/levkropp/samsung-tv-root-untethered")!)
                        }.font(.callout).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    Text("A restore point is saved before supported app changes. Experimental root commands have no automatic backup or undo.").font(.callout).foregroundStyle(.secondary)
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
