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
                .navigationTitle((model.selected?.model ?? model.selectedTizen?.model).map { "\($0) · \(model.section.title)" } ?? "Tether")
        }
        .inspector(isPresented: Binding(get: { model.showInspector && model.section == .debloat && model.selectedTizen == nil }, set: { model.showInspector = $0 })) {
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
        .sheet(item: $model.tizenReportToShow) { TizenReportSheet(box: $0) }
        .confirmationDialog("This TV has a new address", isPresented: Binding(get: { model.tizenAddressChangeRevert != nil }, set: { if !$0 { model.tizenAddressChangeRevert = nil } }), titleVisibility: .visible, presenting: model.tizenAddressChangeRevert) { rp in
            Button("Revert on \(model.selectedTizen?.model ?? "this TV")") { Task { await model.revertTizen(rp, addressChangeConfirmed: true) } }
            Button("Cancel", role: .cancel) {}
        } message: { rp in
            Text("This restore point was saved at \(rp.device.serial); the TV is now at \(model.selectedTizen?.serial ?? "?"). Its hardware ID and model match. Only continue if it's the same TV.")
        }
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
        .confirmationDialog("This device has a new address", isPresented: Binding(get: { model.addressChangeRevert != nil }, set: { if !$0 { model.addressChangeRevert = nil } }), titleVisibility: .visible, presenting: model.addressChangeRevert) { rp in
            Button("Revert on \(model.selected?.model ?? "this device")") { Task { await model.revert(rp, addressChangeConfirmed: true) } }
            Button("Cancel", role: .cancel) {}
        } message: { rp in
            Text("This restore point was saved at \(rp.profile.serial); the device is now at \(model.selected?.serial ?? "?"). The hardware serial, vendor and model match. Only continue if it's the same \(rp.profile.model).")
        }
        .alert(model.alert?.title ?? "", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK") { model.alert = nil }
        } message: { Text(model.alert?.message ?? "") }
        .overlay(alignment: .bottom) { ToastHost() }
        .overlay(alignment: .top) { UpdateBanner() }
        .alert("Tether is beta software", isPresented: $model.showBetaNotice) {
            Button("I understand") { UserDefaults.standard.set(true, forKey: "betaAcknowledged") }
        } message: {
            Text("Tether changes settings and removes apps on your devices. It saves a restore point first and most changes can be undone, but it has had very little real-device testing. Use it at your own risk, on devices you own and can recover.")
        }
        .task {
            try? await Task.sleep(for: .seconds(3))
            while !Task.isCancelled {
                await model.checkForUpdates()
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
        .task {
            while !Task.isCancelled {
                await model.pollDevices()
                await model.pollTizen()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
}

struct DetailRouter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.selected == nil && model.selectedTizen == nil {
            ContentUnavailableView {
                Label("No device connected", systemImage: "tv.slash")
            } description: {
                Text("Turn on network debugging on your Fire TV or Android device, or Developer Mode on a Samsung TV, then add it.")
            } actions: {
                Button("Add device") { model.showPairing = true }
                    .buttonStyle(.glassProminent)
            }
        } else if model.selectedTizen != nil {
            switch model.section {
            case .overview: TizenOverviewView()
            case .debloat: TizenDebloatView()
            case .apps: TizenAppsView()
            case .backups: TizenBackupsView()
            default: ContentUnavailableView("Not available for TVs", systemImage: "tv", description: Text("This section is for Android and Fire OS devices."))
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
                        .buttonStyle(.glass).disabled(model.isBusy)
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
            Text(r.applied.isEmpty ? "Nothing was applied." : "Applied" + (r.verified ? ", confirmed on the device:" : ", but couldn't confirm on the device:"))
            changeList(r.applied)
            if let (change, error) = r.failed {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stopped at: \(describe(change))").fontWeight(.medium)
                    Text(error.advice).foregroundStyle(.secondary)
                    if !r.pending.isEmpty {
                        Text("Not applied:").foregroundStyle(.secondary)
                        changeList(r.pending)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 10))
            }
            Text("A restore point was saved before anything changed.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                // Always offered: the failed change may still have landed, and the planner skips what needs no undo.
                Button("Revert") { dismiss(); Task { await model.revert(r.restorePoint) } }.disabled(model.isBusy)
                Button("Done") { dismiss() }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 460)
    }

    private func changeList(_ changes: [Change]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                Text("• \(describe(change))").font(.callout).foregroundStyle(.secondary)
            }
        }
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
