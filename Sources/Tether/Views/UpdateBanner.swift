import SwiftUI
import TetherCore

/// A floating glass capsule at the top: a new version is ready, or one is being installed.
struct UpdateBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.updateStatus {
        case .available(let info) where !model.updateDismissed:
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.tint)
                Text("Tether \(info.version) is available").lineLimit(1)
                if let page = info.pageURL { Link("What's new", destination: page).font(.callout) }
                Button("Update & restart") { Task { await model.installUpdate() } }.buttonStyle(.glassProminent).disabled(model.isBusy)
                Button("Later") { model.updateDismissed = true }.buttonStyle(.glass)
            }
            .bannerStyle()
        case .installing(let step):
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(step).lineLimit(1)
            }
            .bannerStyle()
        default:
            EmptyView()
        }
    }
}

private extension View {
    func bannerStyle() -> some View {
        self.padding(.horizontal, 16).padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
    }
}
