import Foundation

/// Samsung's shell launcher splits its classpath at spaces in Application Support.
/// Run the same bundled Java entry point directly with distinct Process arguments.
enum TizenCLI {
    struct Invocation: Sendable {
        let executable: URL
        let arguments: [String]
        let directory: URL?
    }

    static func invocation(_ cli: URL, _ arguments: [String]) -> Invocation {
        let bin = cli.deletingLastPathComponent()
        let ide = bin.deletingLastPathComponent()
        let root = ide.deletingLastPathComponent().deletingLastPathComponent()
        let java = root.appendingPathComponent("jdk/Contents/Home/bin/java")
        let libraries = ide.appendingPathComponent("lib-ncli")
        let config = ide.appendingPathComponent("conf-ncli")
        guard FileManager.default.isExecutableFile(atPath: java.path),
              let jars = try? FileManager.default.contentsOfDirectory(at: libraries, includingPropertiesForKeys: nil),
              !jars.isEmpty else {
            return Invocation(executable: cli, arguments: arguments, directory: nil)
        }
        let classpath = ([config.path] + jars.filter { $0.pathExtension == "jar" }.map(\.path).sorted()
                         + [root.appendingPathComponent("library/sdk-utils-core.jar").path]).joined(separator: ":")
        return Invocation(executable: java, arguments: [
            "-Dlog4j.configurationFile=\(config.appendingPathComponent("log4j-progress.xml").path)",
            "-Djava.library.path=\(libraries.appendingPathComponent("spawner").path)",
            "-cp", classpath, "org.tizen.ncli.ide.shell.Main",
        ] + arguments + ["--current-workspace-path", bin.path], directory: bin)
    }

    static func run(_ cli: URL, _ arguments: [String], timeout: Duration = .seconds(30)) async throws -> (status: Int32, out: String, err: String) {
        let command = invocation(cli, arguments)
        return try await ProcessRunner.run(command.executable, command.arguments, timeout: timeout, currentDirectory: command.directory)
    }
}
