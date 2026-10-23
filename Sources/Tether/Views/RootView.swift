import SwiftUI
import TetherCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 320)
        } detail: {
            DetailRouter()
                .navigationTitle(model.selected.map { "\($0.model) · \(model.section.title)" } ?? "Tether")
        }
        .inspector(isPresented: Binding(get: { model.showInspector && model.section == .debloat }, set: { model.showInspector = $0 })) {
            InspectorView().inspectorColumnWidth(min: 260, ideal: 320, max: 400)
        }
        .toolbar {
            ToolbarItem {
                Button("Add device", systemImage: "plus") { model.showPairing = true }
                    .help("Add a device")
            }
            ToolbarItem {
                Button("Toggle details", systemImage: "sidebar.trailing") { model.showInspector.toggle() }
                    .help("Show or hide details")
                    .disabled(model.section != .debloat)
            }
        }
        .sheet(isPresented: $model.showPairing) { PairingSheet() }
        .sheet(item: $model.reportToShow) { ReportSheet(box: $0) }
        .sheet(item: $model.pendingChoice, onDismiss: { model.pendingChoice?.resolve(nil) }) { request in
            VStack(alignment: .leading, spacing: 12) {
                Text("Which file?").font(.title3.weight(.semibold))
                Text("Several downloads fit this device.").foregroundStyle(.secondary)
                ForEach(request.options, id: \.name) { asset in
                    Button(asset.name) { request.resolve(asset); model.pendingChoice = nil }.buttonStyle(.glass)
                }
                Button("Cancel") { request.resolve(nil); model.pendingChoice = nil }.keyboardShortcut(.cancelAction)
            }
            .padding(24).frame(width: 380)
        }
        .alert(model.alert?.title ?? "", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK") { model.alert = nil }
        } message: { Text(model.alert?.message ?? "") }
        .overlay(alignment: .bottom) { ToastHost() }
        .task {
            while !Task.isCancelled {
                await model.pollDevices()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
}

struct DetailRouter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.selected == nil {
            ContentUnavailableView {
                Label("No device connected", systemImage: "tv.slash")
            } description: {
                Text("Turn on network debugging on your Fire TV or Android device, then add it.")
            } actions: {
                Button("Add device") { model.showPairing = true }
                    .buttonStyle(.glassProminent)
            }
        } else {
            switch model.section {
            case .overview: OverviewView()
            case .debloat: DebloatView()
            case .tweaks: TweaksView()
            case .apps: AppsView()
            case .backups: BackupsView()
            case .console: ConsoleView()
            }
        }
    }
}

struct ToastHost: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let toast = model.toast {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(toast.message).lineLimit(1)
                if let undo = toast.undo {
                    Button("Undo") { model.toast = nil; Task { await model.revert(undo) } }
                        .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(6))
                if model.toast?.id == toast.id { withAnimation(Theme.smooth) { model.toast = nil } }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

struct ReportSheet: View {
    let box: ReportBox
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let r = box.report
        VStack(alignment: .leading, spacing: 16) {
            Label(box.title, systemImage: r.failed == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(r.failed == nil ? Color.green : Color.orange)
            Text("\(r.applied.count) change\(r.applied.count == 1 ? "" : "s") applied" + (r.verified ? ", confirmed on the device." : "; couldn't confirm on the device."))
            if let (change, error) = r.failed {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stopped at: \(describe(change))").fontWeight(.medium)
                    Text(error.advice).foregroundStyle(.secondary)
                    if !r.pending.isEmpty { Text("\(r.pending.count) more not applied.").foregroundStyle(.secondary) }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 10))
            }
            Text("A restore point was saved before anything changed.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                if !r.applied.isEmpty {
                    Button("Revert") { dismiss(); Task { await model.revert(r.restorePoint) } }
                }
                Button("Done") { dismiss() }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 460)
    }

    private func describe(_ change: Change) -> String {
        switch change {
        case .removePackage(let p): "remove \(p.value)"
        case .restorePackage(let p): "restore \(p.value)"
        case .setSetting(_, let k, let v): "set \(k) to \(v)"
        case .deleteSetting(_, let k): "reset \(k)"
        case .setDensity(let d): d.map { "set density to \($0)" } ?? "reset density"
        case .setHome(let c): "set launcher \(c)"
        case .revokePermission(let p, _), .grantPermission(let p, _): "change a permission for \(p.value)"
        }
    }
}
