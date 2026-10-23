import SwiftUI
import TetherCore

struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let entry = model.inspected {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(entry.title).font(.title3.weight(.semibold))
                    HStack { TierBadge(tier: entry.tier); status(entry) }
                    Text(entry.package.value).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(entry.description)
                    if let breaks = entry.breaks {
                        Label { Text(breaks) } icon: { Image(systemName: "exclamationmark.triangle") }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.14), in: .rect(cornerRadius: 10))
                            .accessibilityLabel("What may break: \(breaks)")
                    }
                    history(entry)
                    Text("Source: \(entry.source)").font(.caption).foregroundStyle(.secondary)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView("Select an app", systemImage: "sidebar.right", description: Text("Details, risks and revert history appear here."))
        }
    }

    private func status(_ entry: CatalogEntry) -> some View {
        let state = model.snapshot?.state(of: entry.package)
        return Text(state == .removedForUser ? "Removed" : state == .disabled ? "Disabled" : "Installed").font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private func history(_ entry: CatalogEntry) -> some View {
        let past = model.restorePoints.filter { $0.changes.contains(.removePackage(entry.package)) }
        if !past.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("History").font(.headline)
                ForEach(past) { rp in
                    HStack {
                        Text(rp.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.callout)
                        Spacer()
                        Button("Revert batch (\(rp.changes.count))") { Task { await model.revert(rp) } }.buttonStyle(.glass).controlSize(.small).disabled(model.isBusy)
                    }
                }
            }
        }
    }
}
