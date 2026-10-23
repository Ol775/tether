import Foundation
@testable import TetherCore

/// Copies the scripted `fake-adb` into its own temp dir; state files live beside the script.
struct FakeADB {
    let dir: URL
    let runner: ADBRunner

    init(files: [String: String] = [:]) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("fakeadb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let src = Bundle.module.url(forResource: "fake-adb", withExtension: nil, subdirectory: "Fixtures")!
        let exe = dir.appendingPathComponent("fake-adb")
        try FileManager.default.copyItem(at: src, to: exe)
        for (name, text) in files {
            try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        runner = ADBRunner(executable: exe)
    }

    func calls() -> [String] { lines("calls.log") }

    func lines(_ file: String) -> [String] {
        let text = (try? String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }
}
