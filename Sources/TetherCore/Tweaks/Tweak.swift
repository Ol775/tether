public struct TweakOption: Equatable, Sendable {
    public let label: String
    public let changes: [Change]
}

public struct Tweak: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let platforms: [Platform]
    public let options: [TweakOption]
}
