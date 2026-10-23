import Foundation

public enum ProcessRunnerError: Error, Equatable, Sendable {
    case launchFailed, timeout
}

/// Runs a child process with output captured via temp files (so a chatty child can never fill a pipe and
/// deadlock us), kills it on timeout or cancellation, and returns what it printed.
enum ProcessRunner {
    static func run(_ exe: URL, _ args: [String], timeout: Duration, currentDirectory: URL? = nil, environment: [String: String] = [:]) async throws -> (status: Int32, out: String, err: String) {
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
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.standardOutput = outH
        process.standardError = errH
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { throw ProcessRunnerError.launchFailed }

        let deadline = ContinuousClock.now + timeout
        try await withTaskCancellationHandler {
            while process.isRunning {
                if ContinuousClock.now >= deadline { terminateTree(process); throw ProcessRunnerError.timeout }
                try await Task.sleep(for: .milliseconds(10))
            }
        } onCancel: { terminateTree(process) }

        let out = String(decoding: (try? Data(contentsOf: outURL)) ?? Data(), as: UTF8.self)
        let err = String(decoding: (try? Data(contentsOf: errURL)) ?? Data(), as: UTF8.self)
        return (process.terminationStatus, out, err)
    }

    /// npm and similar tools spawn grandchildren (webpack, node) that outlive a plain `terminate()`, so signal descendants first.
    static func terminateTree(_ process: Process) {
        func descendants(of pid: pid_t) -> [pid_t] {
            let pgrep = Process()
            pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            pgrep.arguments = ["-P", String(pid)]
            let pipe = Pipe()
            pgrep.standardOutput = pipe
            pgrep.standardError = FileHandle.nullDevice
            guard (try? pgrep.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            pgrep.waitUntilExit()
            let children = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { pid_t($0) }
            return children.flatMap { descendants(of: $0) } + children
        }
        guard process.isRunning else { return }
        for pid in descendants(of: process.processIdentifier) { kill(pid, SIGTERM) }
        process.terminate()
    }
}
