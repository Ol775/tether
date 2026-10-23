import SwiftUI
import TetherCore

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: Binding<Pane?>(get: { model.section }, set: { if let pane = $0 { model.section = pane } })) {
            SwiftUI.Section("Devices") {
                if model.devices.isEmpty {
                    Text("None connected").foregroundStyle(.secondary)
                }
                ForEach(model.devices) { device in
                    DeviceRow(device: device, isSelected: device.serial == model.selectedSerial)
                }
            }
            SwiftUI.Section("Manage") {
                ForEach(Pane.allCases) { pane in
                    Label(pane.title, systemImage: pane.symbol).tag(pane)
                }
                .disabled(model.selected == nil)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { model.showPairing = true } label: {
                Label("Add device", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .padding(12)
        }
    }
}

struct DeviceRow: View {
    let device: DeviceProfile
    let isSelected: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { Task { await model.select(device.serial) } } label: {
            HStack(spacing: 10) {
                Image(systemName: device.platform == .fireOS ? "tv" : "smartphone")
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.model).fontWeight(isSelected ? .semibold : .regular)
                    Text(device.serial).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(.green).frame(width: 7, height: 7).accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressScaleStyle())
        .listRowBackground(isSelected ? RoundedRectangle(cornerRadius: 8).fill(.selection.opacity(0.35)) : nil)
        .accessibilityLabel("\(device.model), connected, \(device.serial)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
