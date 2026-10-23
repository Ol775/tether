import Foundation

/// Runs the bundled `adb` on a private server port so it never fights a system adb.
public actor ADBRunner {
    private let executable: URL
    private let port: Int

    public init(executable: URL, port: Int = 5038) {
        self.executable = executable
        self.port = port
    }

    public func run(_ args: [String], serial: String? = nil, timeout: Duration = .seconds(15)) async throws -> String {
        var full = ["-P", String(port)]
        if let serial { full += ["-s", serial] }
        full += args
        return try await Self.exec(executable, full, timeout: timeout)
    }

    // Output goes to temp files, so a chatty child can never fill a pipe and deadlock us.
    private static func exec(_ exe: URL, _ args: [String], timeout: Duration) async throws -> String {
        let tmp = FileManager.default.temporaryDirectory
        let outURL = tmp.appendingPathComponent("adb-\(UUID().uuidString).out")
        let errURL = tmp.appendingPathComponent("adb-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outURL); try? FileManager.default.removeItem(at: errURL) }

        let outH = try FileHandle(forWritingTo: outURL)
        let errH = try FileHandle(forWritingTo: errURL)
        defer { try? outH.close(); try? errH.close() }

        let process = Process()
        process.executableURL = exe
        process.arguments = args
        process.standardOutput = outH
        process.standardError = errH
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { throw ADBError.adbMissing }

        let deadline = ContinuousClock.now + timeout
        try await withTaskCancellationHandler {
            while process.isRunning {
                if ContinuousClock.now >= deadline { process.terminate(); throw ADBError.timeout }
                try await Task.sleep(for: .milliseconds(10))
            }
        } onCancel: { process.terminate() }

        let out = String(decoding: (try? Data(contentsOf: outURL)) ?? Data(), as: UTF8.self)
        let err = String(decoding: (try? Data(contentsOf: errURL)) ?? Data(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw ADBError.classify(code: process.terminationStatus, output: err.isEmpty ? out : err + out)
        }
        return out
    }
}
