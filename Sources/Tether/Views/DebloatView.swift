import SwiftUI
import TetherCore

struct DebloatView: View {
    @Environment(AppModel.self) private var model

    private enum Mode: String, CaseIterable, Identifiable {
        case installed = "Installed", removed = "Removed"
        var id: String { rawValue }
    }

    @State private var selection: Set<String> = []
    @State private var search = ""
    @State private var showExpert = false
    @State private var mode: Mode = .installed
    @State private var confirming = false
    @State private var seededFor: String?

    private var entries: [CatalogEntry] {
        let all = mode == .installed ? model.visibleCatalogEntries : model.removedCatalogEntries
        return all.filter { showExpert || $0.tier != .expert }
            .filter { search.isEmpty || [$0.title, $0.package.value, $0.description].contains { $0.localizedCaseInsensitiveContains(search) } }
    }

    private var chosen: [CatalogEntry] { entries.filter { selection.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Show", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                Spacer()
                Toggle("Show expert items", isOn: $showExpert.animation(Theme.smooth)).toggleStyle(.switch).controlSize(.small)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)

            if entries.isEmpty {
                ContentUnavailableView(mode == .installed ? "Nothing to remove" : "Nothing removed yet",
                                       systemImage: mode == .installed ? "checkmark.seal" : "tray",
                                       description: Text(search.isEmpty ? "Apps from the catalog that this device has installed show up here." : "No matches for “\(search)”."))
            } else {
                List(selection: Binding<String?>(get: { model.inspected?.id }, set: { id in model.inspected = entries.first { $0.id == id } })) {
                    ForEach(RiskTier.allCases, id: \.self) { tier in
                        let rows = entries.filter { $0.tier == tier }
                        if !rows.isEmpty {
                            SwiftUI.Section {
                                ForEach(rows) { entry in row(entry).tag(entry.id) }
                            } header: {
                                HStack(spacing: 8) { TierBadge(tier: tier); Text(Self.blurb(tier)).foregroundStyle(.secondary) }.textCase(nil).padding(.vertical, 4)
                            }
                        }
                    }
                }
                .animation(Theme.smooth, value: entries.map(\.id))
            }
        }
        .searchable(text: $search, prompt: "Search apps")
        .safeAreaInset(edge: .bottom) {
            if mode == .installed && !chosen.isEmpty {
                ActionBar(count: chosen.count) { confirming = true }
                    .disabled(model.isBusy)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.smooth, value: chosen.isEmpty)
        .sheet(isPresented: $confirming) {
            ConfirmRemovalSheet(entries: chosen) {
                let removing = chosen
                selection.subtract(removing.map(\.id))
                Task { await model.apply(removing.map { .removePackage($0.package) }, reason: "Removed \(removing.count) app\(removing.count == 1 ? "" : "s")", showReport: true) }
            }
        }
        .onAppear(perform: seed)
        .onChange(of: model.selectedSerial) { seed() }
        .onChange(of: model.visibleCatalogEntries.map(\.id)) { seed() }
    }

    @ViewBuilder private func row(_ entry: CatalogEntry) -> some View {
        HStack(spacing: 12) {
            if mode == .installed {
                Toggle("Remove \(entry.title)", isOn: Binding(get: { selection.contains(entry.id) },
                                                              set: { on in if on { selection.insert(entry.id) } else { selection.remove(entry.id) } }))
                    .toggleStyle(.checkbox).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                Text(entry.description).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if mode == .removed {
                Button("Restore") { Task { await model.apply([.restorePackage(entry.package)], reason: "Restored \(entry.title)") } }
                    .buttonStyle(.glass).controlSize(.small).disabled(model.isBusy)
            }
        }
        .padding(.vertical, 3)
    }

    private func seed() {
        // Data arrives after the view appears, so seed once per device as soon as entries exist.
        guard let serial = model.selectedSerial, seededFor != serial, !model.visibleCatalogEntries.isEmpty else { return }
        seededFor = serial
        selection = Set(model.visibleCatalogEntries.filter { $0.tier == .safe }.map(\.id))
    }

    private static func blurb(_ tier: RiskTier) -> String {
        switch tier {
        case .safe: "Nothing you'll miss"
        case .recommended: "Usually fine to remove"
        case .advanced: "May affect features"
        case .expert: "Can break the device"
        }
    }
}

private struct ActionBar: View {
    let count: Int
    let review: () -> Void

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 14) {
                Text("Remove \(count) · restore point will be saved")
                    .contentTransition(.numericText())
                    .animation(Theme.quick, value: count)
                Button("Review…", action: review)
                    .buttonStyle(.glassProminent)
            }
            .padding(.leading, 20).padding(.trailing, 8).padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ConfirmRemovalSheet: View {
    let entries: [CatalogEntry]
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var understood = false

    private var risky: Bool { entries.contains { $0.tier >= .advanced } }
    private var needsAck: Bool { entries.contains { $0.tier == .expert } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remove \(entries.count) app\(entries.count == 1 ? "" : "s")?").font(.title3.weight(.semibold))
            Text("Tether saves a restore point first, so you can undo this from Backups.").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text(entry.title).fontWeight(.medium); TierBadge(tier: entry.tier) }
                            if let breaks = entry.breaks { Text(breaks).font(.callout).foregroundStyle(.orange) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
            if needsAck { Toggle("I understand this can break the device", isOn: $understood) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(risky ? "Remove anyway" : "Remove") { dismiss(); confirm() }
                    .buttonStyle(.glassProminent).tint(risky ? .orange : nil)
                    .keyboardShortcut(.defaultAction).disabled(needsAck && !understood)
            }
        }
        .padding(24).frame(width: 480)
    }
}
