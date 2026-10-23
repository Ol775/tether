public enum ADBError: Error, Equatable, Sendable {
    case adbMissing
    case timeout
    case unauthorized
    case offline
    case noPermission(String)
    case commandFailed(code: Int32, stderr: String)

    /// Plain-English next step for the user.
    public var advice: String {
        switch self {
        case .adbMissing: "The bundled adb tool is missing. Rebuild the app with scripts/bundle.sh."
        case .timeout: "The device didn't answer in time. Check it is on and on the same network, then retry."
        case .unauthorized: "Accept the \"Allow debugging\" prompt on the device (tick \"Always allow\"), then retry."
        case .offline: "The device went offline. Check power and Wi-Fi, then reconnect it."
        case .noPermission: "The device refused this action. It may be protected or need a different permission."
        case .commandFailed(_, let stderr): stderr.isEmpty ? "The command failed." : stderr
        }
    }

    static func classify(code: Int32, output: String) -> ADBError {
        let text = output.lowercased()
        if text.contains("unauthorized") || text.contains("failed to authenticate") { return .unauthorized }
        if text.contains("device offline") || text.contains("no devices/emulators") || text.contains("not found") && text.contains("device '") {
            return .offline
        }
        if text.contains("permission denied") || text.contains("securityexception") {
            return .noPermission(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return .commandFailed(code: code, stderr: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
