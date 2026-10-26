import Foundation

public enum AppRelauncher {
    /// Spawn before quitting. Arguments are passed separately, so spaces and shell metacharacters in paths are safe.
    public static func prepare(app: URL, waitingForPID pid: Int32 = ProcessInfo.processInfo.processIdentifier) throws {
        guard app.pathExtension == "app", pid > 0,
              FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/Tether").path)
        else { throw CocoaError(.fileNoSuchFile) }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/zsh")
        helper.arguments = ["-c", """
        for attempt in {1..200}; do
          if ! kill -0 "$1" 2>/dev/null; then
            exec /usr/bin/open -n "$2"
          fi
          /bin/sleep 0.1
        done
        exit 1
        """, "tether-relaunch", String(pid), app.path]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
    }
}
