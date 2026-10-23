import Foundation

/// Follows jellyfin/jellyfin-tizen's documented source build, pinned to an exact Tizen commit and Web tag.
public struct JellyfinTizenBuilder: Sendable {
    struct Step: Sendable {
        enum Tool: Sendable { case git, npm, tizen }
        let label: String
        let tool: Tool
        let arguments: [String]
        let directory: URL
        let environment: [String: String]
        init(_ label: String, _ tool: Tool, _ arguments: [String], _ directory: URL, _ environment: [String: String] = [:]) {
            self.label = label; self.tool = tool; self.arguments = arguments; self.directory = directory; self.environment = environment
        }
    }

    private let cli: URL
    public init(cli: URL) { self.cli = cli }

    static func steps(root: URL, version: String, commit: String, profile: String) throws -> [Step] {
        guard let version = Jellyfin.stableVersion(version) else { throw JellyfinError.invalidVersion }
        guard Jellyfin.validCommit(commit) else { throw JellyfinError.invalidCommit }
        guard !profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !profile.contains("\n") else {
            throw JellyfinError.buildFailed("Choose a Samsung TV certificate profile first.")
        }
        let web = root.appendingPathComponent("jellyfin-web")
        let tizen = root.appendingPathComponent("jellyfin-tizen")
        return [
            Step("Downloading official Jellyfin Web \(version)…", .git,
                 ["clone", "--depth", "1", "--branch", "v\(version)", "https://github.com/jellyfin/jellyfin-web.git", web.path], root),
            Step("Preparing Tizen source…", .git, ["init", tizen.path], root),
            Step("Selecting official Tizen repository…", .git, ["remote", "add", "origin", "https://github.com/jellyfin/jellyfin-tizen.git"], tizen),
            Step("Downloading Tizen revision \(commit.prefix(8))…", .git, ["fetch", "--depth", "1", "origin", commit], tizen),
            Step("Checking out Tizen source…", .git, ["checkout", "--detach", "FETCH_HEAD"], tizen),
            Step("Installing Web build dependencies…", .npm, ["ci", "--no-audit", "--no-fund"], web),
            Step("Building Jellyfin Web (this can take several minutes)…", .npm, ["run", "build:production"], web, ["USE_SYSTEM_FONTS": "1"]),
            Step("Building the Tizen interface…", .npm, ["ci", "--no-audit", "--no-fund"], tizen, ["JELLYFIN_WEB_DIR": web.appendingPathComponent("dist").path]),
            Step("Building the TV application…", .tizen, ["build-web", "-e", ".*", "-e", "gulpfile.babel.js", "-e", "README.md", "-e", "node_modules/*", "-e", "package*.json", "-e", "yarn.lock", "--", tizen.path], tizen),
            Step("Signing with your Samsung TV profile…", .tizen, ["package", "-t", "wgt", "-s", profile, "-o", root.path, "--", tizen.appendingPathComponent(".buildResult").path], tizen),
        ]
    }

    /// Samsung gates `developer.samsung.com/privilege/*` behind a Partner-level certificate; an
    /// individual's Public certificate can only sign a package that doesn't request one. Dropping it
    /// (currently just `productinfo`, used for device-info reporting, not playback) lets a Public-signed
    /// build install at all. One line of config.xml per tag, confirmed against a real build's output.
    static func stripPartnerPrivileges(at configURL: URL) throws {
        let text = try String(contentsOf: configURL, encoding: .utf8)
        let kept = text.components(separatedBy: "\n").filter { !$0.contains("developer.samsung.com/privilege/") }
        try kept.joined(separator: "\n").write(to: configURL, atomically: true, encoding: .utf8)
    }

    public func build(version: String, commit: String, profile: String, cache: URL,
                      progress: @escaping @Sendable (String) -> Void) async throws -> JellyfinBuild {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("tether-jellyfin-\(UUID())")
        let plan = try Self.steps(root: work, version: version, commit: commit, profile: profile)
        let npm = try Self.tool("npm")
        let node = try Self.tool("node")
        let git = try Self.tool("git")
        let nodeResult = try await ProcessRunner.run(node, ["--version"], timeout: .seconds(10))
        guard nodeResult.status == 0, let major = Int(nodeResult.out.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst().split(separator: ".").first ?? ""), major >= 20 else {
            throw JellyfinError.missingTools
        }
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let path = [node.deletingLastPathComponent().path, npm.deletingLastPathComponent().path,
                    "/opt/homebrew/bin", "/usr/local/bin", ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        for step in plan {
            try Task.checkCancellation()
            progress(step.label)
            let result: (status: Int32, out: String, err: String)
            if case .tizen = step.tool {
                result = try await TizenCLI.run(cli, step.arguments, timeout: .seconds(600))
            } else {
                let executable: URL
                switch step.tool { case .git: executable = git; case .npm: executable = npm; case .tizen: throw JellyfinError.missingTools }
                result = try await ProcessRunner.run(executable, step.arguments, timeout: .seconds(1800), currentDirectory: step.directory,
                                                     environment: step.environment.merging(["PATH": path, "GIT_TERMINAL_PROMPT": "0"]) { _, new in new })
            }
            guard result.status == 0 else {
                throw JellyfinError.buildFailed(step.label + "\n" + String((result.err + result.out).suffix(2500)))
            }
            if step.label.hasPrefix("Building the TV application") {
                try Self.stripPartnerPrivileges(at: work.appendingPathComponent("jellyfin-tizen/.buildResult/config.xml"))
            }
        }
        try Task.checkCancellation()
        let built = work.appendingPathComponent("Jellyfin.wgt")
        guard FileManager.default.fileExists(atPath: built.path) else { throw JellyfinError.buildFailed("Samsung's tools didn't produce Jellyfin.wgt.") }
        let config = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-p", built.path, "config.xml"], timeout: .seconds(30))
        guard config.status == 0, Self.declaresJellyfin(config.out) else {
            throw JellyfinError.buildFailed("The signed package isn't the official Jellyfin app (\(Jellyfin.tizenID.value)), so it was not installed.")
        }
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let dest = cache.appendingPathComponent("Jellyfin-\(UUID()).wgt")
        try FileManager.default.copyItem(at: built, to: dest)
        return JellyfinBuild(webVersion: Jellyfin.stableVersion(version)!, tizenCommit: commit, profile: profile, package: dest)
    }

    /// The package's own config.xml must name the fixed official application id.
    static func declaresJellyfin(_ configXML: String) -> Bool {
        configXML.contains("id=\"\(Jellyfin.tizenID.value)\"")
    }

    private static func tool(_ name: String) throws -> URL {
        let folders = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        guard let file = folders.map({ URL(fileURLWithPath: $0).appendingPathComponent(name) })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { throw JellyfinError.missingTools }
        return file
    }
}
