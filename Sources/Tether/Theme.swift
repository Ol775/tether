import SwiftUI
import TetherCore

enum Theme {
    static let quick = Animation.snappy(duration: 0.2)
    static let smooth = Animation.smooth(duration: 0.22)

    static func tierColor(_ tier: RiskTier) -> Color {
        switch tier {
        case .safe: .green
        case .recommended: .blue
        case .advanced: .orange
        case .expert: .red
        }
    }

    static func tierSymbol(_ tier: RiskTier) -> String {
        switch tier {
        case .safe: "checkmark.shield"
        case .recommended: "hand.thumbsup"
        case .advanced: "exclamationmark.triangle"
        case .expert: "xmark.octagon"
        }
    }

    static func tierLabel(_ tier: RiskTier) -> String { tier.rawValue.capitalized }
}

/// Subtle press feedback; no scale at all when Reduce Motion is on.
struct PressScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : Theme.quick, value: configuration.isPressed)
    }
}

/// Risk tier as colour + icon + word, so it never relies on colour alone.
struct TierBadge: View {
    let tier: RiskTier

    var body: some View {
        Label(Theme.tierLabel(tier), systemImage: Theme.tierSymbol(tier))
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.tierColor(tier))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.tierColor(tier).opacity(0.14), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Risk: \(Theme.tierLabel(tier))")
    }
}
