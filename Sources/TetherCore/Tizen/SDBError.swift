public enum SDBError: Error, Equatable, Sendable {
    case toolsMissing
    case timeout
    case developerModeOff
    case refused
    case notConnected
    case commandFailed(code: Int32, output: String)

    /// Plain-English next step for the user.
    public var advice: String {
        switch self {
        case .toolsMissing: "Samsung's tools aren't set up yet. Use Set up Samsung tools first."
        case .timeout: "The TV didn't answer in time. Check it is on and on the same network, then retry."
        case .developerModeOff: "Turn on Developer Mode on the TV (Apps, then press 1 2 3 4 5) and enter this Mac's IP address there, then restart the TV."
        case .refused: "The TV refused the connection. Check Developer Mode is on and shows this Mac's IP. Some 2023+ models block this entirely."
        case .notConnected: "The TV isn't connected. Connect to it again."
        case .commandFailed(_, let output): output.isEmpty ? "The command failed." : output
        }
    }

    static func classify(code: Int32, output: String) -> SDBError {
        let text = output.lowercased()
        if text.contains("failed to connect") || text.contains("connection refused") || text.contains("unable to connect") { return .refused }
        if text.contains("developer mode") { return .developerModeOff }
        if text.contains("closed") || text.contains("device offline") || text.contains("no devices") || (text.contains("device") && text.contains("not found")) { return .notConnected }
        return .commandFailed(code: code, output: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
