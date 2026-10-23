import Foundation

public enum ConsoleVerdict: Equatable, Sendable {
    case allow
    case confirm(reason: String)
}

public enum ConsoleError: Error, Equatable, Sendable {
    case needsConfirmation(String)
}

/// Allowlist guard for the raw console: only known read-only commands run unprompted; anything
/// else (including anything it can't parse) needs an explicit confirm. Over-confirming is fine,
/// under-confirming is not, so the command is split on every shell separator, substitution and
/// brace before each piece's verb is checked literally.
public enum ConsoleGuard {
    public static func classify(_ command: String) -> ConsoleVerdict {
        var text = command
        for safeRedirect in [#"\d?>&\d"#, #"&?\d?>\s*/dev/null"#] {
            text = text.replacingOccurrences(of: safeRedirect, with: " ", options: .regularExpression)
        }
        if text.contains(">") { return .confirm(reason: "writes to a file") }

        for segment in text.components(separatedBy: CharacterSet(charactersIn: ";&|\n\r`(){}")) {
            let tokens = segment.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !tokens.isEmpty, case .confirm(let reason) = verdict(tokens) else { continue }
            return .confirm(reason: reason)
        }
        return .allow
    }

    private static let readOnly: Set<String> = [
        "ls", "cat", "echo", "printf", "pwd", "id", "whoami", "uname", "uptime", "df", "du", "ps", "top", "getprop",
        "logcat", "netstat", "which", "stat", "wc", "head", "tail", "grep", "sort", "uniq", "cut", "tr", "ping",
    ]
    private static let readOnlyPM: Set<String> = ["list", "path", "dump", "resolve-activity", "get-install-location", "get-max-users", "has-feature"]
    private static let reasons: [String: String] = [
        "rm": "deletes files", "rmdir": "deletes files", "reboot": "restarts or powers off the device", "shutdown": "restarts or powers off the device",
        "poweroff": "restarts or powers off the device", "dd": "overwrites storage", "mkfs": "overwrites storage", "svc": "can drop the network connection",
        "su": "runs with elevated privileges", "sh": "runs another command", "eval": "runs another command", "mount": "changes storage mounts",
    ]

    private static func verdict(_ tokens: [String]) -> ConsoleVerdict {
        let verb = tokens[0], args = Array(tokens.dropFirst())
        switch verb {
        case _ where readOnly.contains(verb): return .allow
        case "find": return args.contains { ["-delete", "-exec", "-execdir", "-ok", "-okdir", "-fprint", "-fprintf", "-fls"].contains($0) } ? .confirm(reason: "find can delete or run commands") : .allow
        case "date": return args.allSatisfy { $0.hasPrefix("+") } ? .allow : .confirm(reason: "changes the clock")
        case "dumpsys": return args.contains { ["set", "reset", "unplug", "enable", "disable"].contains($0) } ? .confirm(reason: "changes system state") : .allow
        case "settings": return ["get", "list"].contains(args.first ?? "") ? .allow : .confirm(reason: "changes device settings")
        case "pm": return readOnlyPM.contains(args.first ?? "") ? .allow : .confirm(reason: "changes installed apps")
        case "wm": return args == ["size"] || args == ["density"] ? .allow : .confirm(reason: "changes the display")
        default: return .confirm(reason: reasons[verb] ?? "`\(verb)` isn't on the read-only list, so it may change the device")
        }
    }
}

public enum Console {
    /// Raw `adb shell`. Commands the guard flags only run with `confirmed: true`; everything is logged.
    public static func run(_ command: String, on device: DeviceProfile, adb: ADBRunner, log: ChangeLog, confirmed: Bool = false) async throws -> String {
        if case .confirm(let reason) = ConsoleGuard.classify(command), !confirmed { throw ConsoleError.needsConfirmation(reason) }
        await log.append("\(device.serial): console: \(command)")
        do {
            let output = try await adb.run(["shell", command], serial: device.serial)
            await log.append("\(device.serial): console ok")
            return output
        } catch {
            await log.append("\(device.serial): console failed: \(error)")
            throw error
        }
    }
}
