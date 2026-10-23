import Foundation

/// Runs the bundled `adb` on a private server port so it never fights a system adb.
public actor ADBRunner {
    private let executable: URL
    private let port: Int
    private let defaultTimeout: Duration

    /// Pulls and installs move whole APKs over Wi-Fi, so they get minutes rather than the short command timeout.
    public static let transferTimeout: Duration = .seconds(600)

    public init(executable: URL, port: Int = 5038, defaultTimeout: Duration = .seconds(15)) {
        self.executable = executable
        self.port = port
        self.defaultTimeout = defaultTimeout
    }

    public func run(_ args: [String], serial: String? = nil, timeout: Duration? = nil) async throws -> String {
        var full = ["-P", String(port)]
        if let serial { full += ["-s", serial] }
        full += args
        return try await Self.exec(executable, full, timeout: timeout ?? defaultTimeout)
    }

    private static func exec(_ exe: URL, _ args: [String], timeout: Duration) async throws -> String {
        let result: (status: Int32, out: String, err: String)
        do { result = try await ProcessRunner.run(exe, args, timeout: timeout) }
        catch ProcessRunnerError.launchFailed { throw ADBError.adbMissing }
        catch ProcessRunnerError.timeout { throw ADBError.timeout }
        guard result.status == 0 else {
            throw ADBError.classify(code: result.status, output: result.err.isEmpty ? result.out : result.err + result.out)
        }
        return result.out
    }
}
