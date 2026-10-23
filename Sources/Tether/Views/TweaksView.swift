import SwiftUI
import TetherCore

struct TweaksView: View {
    @Environment(AppModel.self) private var model

    private var tweaks: [Tweak] {
        guard let device = model.selected, let snapshot = model.snapshot else { return [] }
        return TweakLibrary.available(for: device.platform, snapshot: snapshot)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(tweaks) { TweakCard(tweak: $0) }
            }
            .padding(24)
        }
    }
}

private struct TweakCard: View {
    let tweak: Tweak
    @Environment(AppModel.self) private var model

    private var current: TweakOption? { model.snapshot.flatMap { TweakLibrary.currentOption(for: tweak, in: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tweak.title).font(.headline)
            Text(tweak.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker(tweak.title, selection: Binding(get: { current?.label ?? "" }, set: choose)) {
                ForEach(tweak.options, id: \.label) { Text($0.label).tag($0.label) }
            }
            .pickerStyle(.segmented).labelsHidden()
            if current == nil {
                Text("Not currently set to any of these.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
        .disabled(model.isBusy)
    }

    private func choose(_ label: String) {
        guard let option = tweak.options.first(where: { $0.label == label }), option != current else { return }
        Task { await model.apply(option.changes, reason: "\(tweak.title): \(option.label)") }
    }
}
