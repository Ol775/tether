import SwiftUI
import TetherCore

struct TizenBackupsView: View {
    @Environment(AppModel.self) private var model
    @State private var deleting: TizenRestorePoint?

    var body: some View {
        if model.tizenRestorePoints.isEmpty {
            ContentUnavailableView("No restore points yet", systemImage: "clock.arrow.circlepath",
                                   description: Text("One is saved automatically before every change."))
        } else {
            List(model.tizenRestorePoints) { rp in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rp.reason).fontWeight(.medium)
                        Text("\(rp.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(rp.apps.count) apps recorded · \(rp.changes.count) change\(rp.changes.count == 1 ? "" : "s")")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Revert") { Task { await model.revertTizen(rp) } }
                        .buttonStyle(.glass)
                        .disabled(!rp.changes.contains { if case .uninstall = $0 { true } else { false } } || model.isBusy)
                        .help("Put back apps this restore point removed, where Tether has the package")
                    Button("Delete", systemImage: "trash") { deleting = rp }
                        .labelStyle(.iconOnly).buttonStyle(.glass)
                }
                .padding(.vertical, 6)
            }
            .confirmationDialog("Delete this restore point?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { rp in
                Button("Delete", role: .destructive) { Task { await model.deleteTizenRestorePoint(rp) } }
            } message: { _ in Text("It can no longer be reverted.") }
        }
    }
}
