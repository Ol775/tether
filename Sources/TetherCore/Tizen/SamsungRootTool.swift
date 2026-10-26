import Foundation

public enum SamsungRootError: Error, LocalizedError, Sendable {
    case invalidTarget, missingTool, missingPayloads, unreviewedVersion(String)
    case confirmationRequired, invalidCommand, failed(String), unverifiedResult

    public var errorDescription: String? {
        switch self {
        case .invalidTarget: "This integration requires a TV IPv4 address on SDB port 26101 and a Mac IPv4 callback address."
        case .missingTool: "Choose an executable samsung-tv-root tool from the project's v0.0.12 release or source installation."
        case .missingPayloads: "The selected folder must contain SamsungTvArchiveRoot.dll and SamsungTvRootAgent.dll. Build or extract the project's matching payloads first."
        case .unreviewedVersion(let version): "This Tether integration targets samsung-tv-root 0.0.12. The selected tool reported \(version)."
        case .confirmationRequired: "Each root attempt needs explicit confirmation, including identity checks."
        case .invalidCommand: "Enter one command of at most 8,192 characters, without NUL characters."
        case .failed(let message): message
        case .unverifiedResult: "The tool did not confirm an authenticated UID 0 session, the requested command, unchanged checked system files and successful cleanup. Completion is unverified."
        }
    }
}

public enum SamsungRootRuntime: String, CaseIterable, Identifiable, Sendable {
    case automatic = "Detect automatically", net31 = ".NET 3.1", net6 = ".NET 6+"
    public var id: String { rawValue }
    public var argument: String? { self == .automatic ? nil : self == .net31 ? "3.1" : "6.0" }
}

/// Immutable request shown to the user before execution. No shell parsing occurs on the Mac.
public struct SamsungRootRequest: Identifiable, Sendable {
    public let id = UUID()
    public let tool: URL
    public let sdb: URL
    public let host: String
    public let callback: String
    public let command: String
    public let runtime: SamsungRootRuntime
    public let payloads: URL?
    public let deviceSerial: String
    public let deviceModel: String

    public init(tool: URL, sdb: URL, device: TizenDevice, callback: String, command: String,
                runtime: SamsungRootRuntime = .automatic, payloads: URL? = nil) throws {
        let endpoint = try ConnectionEndpoint(address: device.serial, port: "26101")
        guard endpoint.port == 26101, Self.isIPv4(endpoint.host), Self.isIPv4(callback),
              callback != "0.0.0.0", callback != "255.255.255.255" else { throw SamsungRootError.invalidTarget }
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              command.count <= 8192, !command.contains("\0") else { throw SamsungRootError.invalidCommand }
        guard tool.isFileURL, tool.path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: tool.path),
              FileManager.default.isExecutableFile(atPath: sdb.path) else { throw SamsungRootError.missingTool }
        if let payloads {
            for name in ["SamsungTvArchiveRoot.dll", "SamsungTvRootAgent.dll"] {
                guard FileManager.default.isReadableFile(atPath: payloads.appendingPathComponent(name).path) else { throw SamsungRootError.missingPayloads }
            }
        }
        self.tool = tool; self.sdb = sdb; self.host = endpoint.host; self.callback = callback
        self.command = command; self.runtime = runtime; self.payloads = payloads
        deviceSerial = device.serial; deviceModel = device.model
    }

    private static func isIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy {
            !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } && UInt8($0) != nil
                && ($0.count == 1 || !$0.hasPrefix("0"))
        }
    }

    var arguments: [String] {
        var args = ["--sdb", sdb.path, "--output", "json", "archive-root", "root", host,
                    "--callback-host", callback, "--bind-host", callback,
                    "--sdb-timeout", "10", "--accept-timeout", "20", "--command-timeout", "30"]
        if let runtime = runtime.argument { args += ["--runtime", runtime] }
        if let payloads { args += ["--payload-directory", payloads.path] }
        args += ["--command", command]
        return args
    }
}

public struct SamsungRootResult: Sendable {
    public let command: String
    public let stdout: String
    public let stderr: String
    public let exitCode: Int?
    public let timedOut: Bool
    public let date: Date
    public let deviceSerial: String

    private struct Evidence: Decodable {
        let host: String
        let authenticated: Bool
        let uid: Int
        let euid: Int
        let system_files_unchanged: Bool
        let staging_cleaned: Bool
        let commands: [Command]
        struct Command: Decodable {
            let command: String
            let stdout: String
            let stderr: String
            let exit_code: Int?
            let timed_out: Bool
        }
    }

    static func parse(_ data: Data, request: SamsungRootRequest) throws -> Self {
        guard data.count <= 1_048_576, let evidence = try? JSONDecoder().decode(Evidence.self, from: data),
              evidence.host == request.host, evidence.authenticated, evidence.uid == 0, evidence.euid == 0,
              evidence.system_files_unchanged, evidence.staging_cleaned, evidence.commands.count == 1,
              let result = evidence.commands.first, result.command == request.command,
              result.exit_code != nil || result.timed_out else { throw SamsungRootError.unverifiedResult }
        return Self(command: result.command, stdout: result.stdout, stderr: result.stderr, exitCode: result.exit_code,
                    timedOut: result.timed_out, date: Date(), deviceSerial: request.deviceSerial)
    }
}

public enum SamsungRootTool {
    public static let reviewedVersion = "0.0.12"
    public static let projectURL = URL(string: "https://github.com/chris-ritsen/samsung-tv-root/tree/v0.0.12")!
    public static let setupURL = URL(string: "https://github.com/chris-ritsen/samsung-tv-root/blob/v0.0.12/QUICKSTART.md")!

    private static var environment: [String: String] {
        ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", "PYTHONUNBUFFERED": "1"]
    }

    public static func checkLocalInstallation(tool: URL, sdb: URL) async throws -> String {
        try await checkVersion(tool)
        let result = try await ProcessRunner.run(tool, ["--sdb", sdb.path, "doctor"], timeout: .seconds(20), environment: environment)
        guard result.status == 0 else { throw SamsungRootError.failed(String((result.err + result.out).prefix(16_384))) }
        return "samsung-tv-root \(reviewedVersion)\n" + String(result.out.prefix(32_768))
    }

    private static func checkVersion(_ tool: URL) async throws {
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { throw SamsungRootError.missingTool }
        let result = try await ProcessRunner.run(tool, ["--version"], timeout: .seconds(8), environment: environment)
        let version = result.out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, version == reviewedVersion else { throw SamsungRootError.unreviewedVersion(String(version.prefix(80))) }
    }

    public static func run(_ request: SamsungRootRequest, confirmed: Bool = false) async throws -> SamsungRootResult {
        guard confirmed else { throw SamsungRootError.confirmationRequired }
        try await checkVersion(request.tool)
        let result: (status: Int32, out: String, err: String)
        do { result = try await ProcessRunner.run(request.tool, request.arguments, timeout: .seconds(180), environment: environment) }
        catch ProcessRunnerError.timeout {
            throw SamsungRootError.failed("The root tool timed out. Command completion and TV cleanup are unverified. Do not assume the command was undone; inspect the TV before retrying.")
        }
        // The external CLI exits nonzero for a failed command even if acquisition and cleanup succeeded.
        if let data = result.out.data(using: .utf8), let parsed = try? SamsungRootResult.parse(data, request: request) { return parsed }
        if result.status != 0 {
            throw SamsungRootError.failed("Root attempt failed; completion and cleanup are unverified.\n" + String((result.err + result.out).prefix(16_384)))
        }
        throw SamsungRootError.unverifiedResult
    }
}
