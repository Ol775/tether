import SwiftUI
import TetherCore

struct TizenDebloatView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Set<TizenAppID> = []
    @State private var search = ""
    @State private var confirming = false

    private var rows: [TizenApp] {
        model.tizenApps.filter { search.isEmpty || [$0.name, $0.id.value].contains { $0.localizedCaseInsensitiveContains(search) } }
    }

    private func entry(_ app: TizenApp) -> TizenCatalogEntry? { model.tizenCatalog?.entries.first { $0.app == app.id } }
    private var chosen: [TizenApp] { model.tizenApps.filter { selection.contains($0.id) && !model.tizenLocked.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            if model.selectedTizen != nil && !(model.selectedTizen?.shellEnabled ?? true) {
                Label("Samsung keeps most preinstalled apps locked on this TV. Tether tries a removal, checks the TV, and remembers what it refuses.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 20).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
            }
            if rows.isEmpty {
                ContentUnavailableView("No apps listed", systemImage: "tv",
                                       description: Text(search.isEmpty ? "The TV didn't return an app list. Check Developer Mode is on and reconnect." : "No matches for “\(search)”."))
            } else {
                List(rows) { app in row(app) }
                    .animation(reduceMotion ? nil : Theme.smooth, value: rows.map(\.id))
            }
        }
        .searchable(text: $search, prompt: "Search apps")
        .safeAreaInset(edge: .bottom) {
            if !chosen.isEmpty {
                ActionBar(count: chosen.count) { confirming = true }
                    .disabled(model.isBusy)
                    .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $confirming) {
            TizenConfirmSheet(apps: chosen, entry: entry) {
                let removing = chosen
                selection.subtract(removing.map(\.id))
                Task { await model.applyTizen(removing.map { .uninstall($0.id) }, reason: "Removed \(removing.count) app\(removing.count == 1 ? "" : "s")") }
            }
        }
    }

    @ViewBuilder private func row(_ app: TizenApp) -> some View {
        let known = entry(app)
        let locked = model.tizenLocked.contains(app.id)
        let likely = known.flatMap { e in model.selectedTizen.map { model.tizenCatalog?.likelyLocked(e, on: $0) ?? false } } ?? false
        HStack(spacing: 12) {
            if locked {
                Image(systemName: "lock.fill").foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
            } else {
                Toggle("Remove \(app.name)", isOn: Binding(get: { selection.contains(app.id) },
                                                           set: { on in if on { selection.insert(app.id) } else { selection.remove(app.id) } }))
                    .toggleStyle(.checkbox).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                Text(locked ? "Locked by Samsung: this TV refused to remove it." : (known?.description ?? app.id.value))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if !locked && likely { Text("Probably locked by Samsung; Tether will try and check.").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let tier = known?.tier { TierBadge(tier: tier) }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

private struct TizenConfirmSheet: View {
    let apps: [TizenApp]
    let entry: (TizenApp) -> TizenCatalogEntry?
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var risky: Bool { apps.contains { (entry($0)?.tier ?? .safe) >= .advanced } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remove \(apps.count) app\(apps.count == 1 ? "" : "s")?").font(.title3.weight(.semibold))
            Text("Tether saves a restore point first. Apps Samsung has locked stay installed and are reported. Apps you installed through Tether can be put back; preinstalled ones usually come back through Smart Hub.")
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(apps) { app in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text(app.name).fontWeight(.medium); if let tier = entry(app)?.tier { TierBadge(tier: tier) } }
                            if let breaks = entry(app)?.breaks { Text(breaks).font(.callout).foregroundStyle(.orange) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(risky ? "Remove anyway" : "Remove") { dismiss(); confirm() }
                    .buttonStyle(.glassProminent).tint(risky ? .orange : nil).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 480)
    }
}
