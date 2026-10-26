import Foundation

/// Runs Samsung's `sdb` for Tizen TVs, mirroring `ADBRunner`.
public actor SDBRunner {
    private let executable: URL
    private let defaultTimeout: Duration
    private var restarting = false

    public init(executable: URL, defaultTimeout: Duration = .seconds(15)) {
        self.executable = executable
        self.defaultTimeout = defaultTimeout
    }

    public func run(_ args: [String], serial: String? = nil, timeout: Duration? = nil) async throws -> String {
        guard !restarting else { throw SDBError.notConnected }
        var full: [String] = []
        if let serial { full += ["-s", serial] }
        full += args
        return try await execute(full, timeout: timeout ?? defaultTimeout)
    }

    /// Samsung uses a shared server on this Mac, so all SDB sessions briefly disconnect.
    public func restartServer() async throws {
        guard !restarting else { throw SDBError.notConnected }
        restarting = true
        defer { restarting = false }
        _ = try await execute(["kill-server"], timeout: .seconds(8))
        _ = try await execute(["start-server"], timeout: .seconds(8))
        _ = try await execute(["devices"], timeout: .seconds(6))
    }

    private func execute(_ full: [String], timeout: Duration) async throws -> String {
        let result: (status: Int32, out: String, err: String)
        do { result = try await ProcessRunner.run(executable, full, timeout: timeout) }
        catch ProcessRunnerError.launchFailed { throw SDBError.toolsMissing }
        catch ProcessRunnerError.timeout { throw SDBError.timeout }
        // sdb sometimes reports failure on stdout with exit 0, so callers also read the text.
        guard result.status == 0 else {
            throw SDBError.classify(code: result.status, output: result.err.isEmpty ? result.out : result.err + result.out)
        }
        return result.out
    }
}
