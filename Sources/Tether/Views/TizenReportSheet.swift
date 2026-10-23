import SwiftUI
import TetherCore

struct TizenReportSheet: View {
    let box: TizenReportBox
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let r = box.report
        let clean = r.failed == nil && r.locked.isEmpty && r.cannotRestore.isEmpty
        VStack(alignment: .leading, spacing: 16) {
            Label(box.title, systemImage: clean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(clean ? Color.green : Color.orange)
            Text(r.applied.isEmpty ? "Nothing was applied." : "Applied" + (r.verified ? ", confirmed on the TV:" : ", but couldn't confirm on the TV:"))
            list(r.applied.map(describe))
            if !r.locked.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Locked by Samsung, left installed:").fontWeight(.medium)
                    list(r.locked.map { name(for: $0) })
                    Text(TizenError.lockedBySamsung(r.locked[0]).advice).foregroundStyle(.secondary).font(.callout)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 10))
            }
            if let (change, error) = r.failed {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stopped at: \(describe(change))").fontWeight(.medium)
                    Text(error.advice).foregroundStyle(.secondary)
                    if !r.pending.isEmpty { Text("Not applied:").foregroundStyle(.secondary); list(r.pending.map(describe)) }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 10))
            }
            if !r.cannotRestore.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't be put back from here:").fontWeight(.medium)
                    list(r.cannotRestore.map { name(for: $0) })
                    Text("Tether only has packages for apps it installed itself. Samsung's own apps usually return through Smart Hub.").foregroundStyle(.secondary).font(.callout)
                }
            }
            Text("A restore point was saved before anything changed.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                if !r.applied.isEmpty || r.failed != nil {
                    Button("Revert") { dismiss(); Task { await model.revertTizen(r.restorePoint) } }.disabled(model.isBusy)
                }
                Button("Done") { dismiss() }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 480)
    }

    private func list(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in Text("• \(item)").font(.callout).foregroundStyle(.secondary) }
        }
    }

    private func name(for id: TizenAppID) -> String { model.tizenApps.first { $0.id == id }?.name ?? id.value }

    private func describe(_ change: TizenChange) -> String {
        switch change {
        case .uninstall(let id): "remove \(name(for: id))"
        case .install(let file): "install \(file.lastPathComponent)"
        }
    }
}
