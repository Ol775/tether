import Foundation

public enum ProcessRunnerError: Error, Equatable, Sendable {
    case launchFailed, timeout
}

/// Runs a child process with output captured via temp files (so a chatty child can never fill a pipe and
/// deadlock us), kills it on timeout or cancellation, and returns what it printed.
enum ProcessRunner {
    static func run(_ exe: URL, _ args: [String], timeout: Duration, currentDirectory: URL? = nil) async throws -> (status: Int32, out: String, err: String) {
        let tmp = FileManager.default.temporaryDirectory
        let outURL = tmp.appendingPathComponent("tether-\(UUID().uuidString).out")
        let errURL = tmp.appendingPathComponent("tether-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outURL); try? FileManager.default.removeItem(at: errURL) }

        let outH = try FileHandle(forWritingTo: outURL)
        let errH = try FileHandle(forWritingTo: errURL)
        defer { try? outH.close(); try? errH.close() }

        let process = Process()
        process.executableURL = exe
        process.arguments = args
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = outH
        process.standardError = errH
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { throw ProcessRunnerError.launchFailed }

        let deadline = ContinuousClock.now + timeout
        try await withTaskCancellationHandler {
            while process.isRunning {
                if ContinuousClock.now >= deadline { process.terminate(); throw ProcessRunnerError.timeout }
                try await Task.sleep(for: .milliseconds(10))
            }
        } onCancel: { process.terminate() }

        let out = String(decoding: (try? Data(contentsOf: outURL)) ?? Data(), as: UTF8.self)
        let err = String(decoding: (try? Data(contentsOf: errURL)) ?? Data(), as: UTF8.self)
        return (process.terminationStatus, out, err)
    }
}
