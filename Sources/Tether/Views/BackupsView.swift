import SwiftUI
import TetherCore

struct BackupsView: View {
    @Environment(AppModel.self) private var model
    @State private var deleting: RestorePoint?

    var body: some View {
        if model.restorePoints.isEmpty {
            ContentUnavailableView("No restore points yet", systemImage: "clock.arrow.circlepath",
                                   description: Text("One is saved automatically before every change. You can also make one from Overview."))
        } else {
            List(model.restorePoints) { rp in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rp.reason).fontWeight(.medium)
                        Text("\(rp.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(rp.packages.count) apps recorded · \(rp.apks.count) APK\(rp.apks.count == 1 ? "" : "s") saved · \(rp.changes.count) change\(rp.changes.count == 1 ? "" : "s")")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Revert") { Task { await model.revert(rp) } }
                        .buttonStyle(.glass).disabled(rp.changes.isEmpty || model.isBusy)
                        .help(rp.changes.isEmpty ? "A manual snapshot has no changes to undo." : "Undo what this restore point was saved for")
                    Button("Show in Finder", systemImage: "folder") { model.revealRestorePoint(rp) }
                        .labelStyle(.iconOnly).buttonStyle(.glass)
                    Button("Delete", systemImage: "trash") { deleting = rp }
                        .labelStyle(.iconOnly).buttonStyle(.glass)
                }
                .padding(.vertical, 6)
            }
            .confirmationDialog("Delete this restore point?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { rp in
                Button("Delete", role: .destructive) { Task { await model.deleteRestorePoint(rp) } }
            } message: { _ in Text("Its saved APKs go too, so it can no longer be reverted.") }
        }
    }
}
