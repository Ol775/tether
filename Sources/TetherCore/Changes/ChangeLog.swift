import Foundation

/// Append-only JSON-lines record of everything Tether did to a device.
public actor ChangeLog {
    private let file: URL

    public init(file: URL) { self.file = file }

    public func append(_ message: String) {
        let entry: [String: String] = ["time": ISO8601DateFormatter().string(from: Date()), "message": message]
        guard var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: file)
        }
    }
}
