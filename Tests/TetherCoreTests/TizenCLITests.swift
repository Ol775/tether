import Foundation
import Testing
@testable import TetherCore

struct TizenCLITests {
    @Test func bundledJavaKeepsPathsWithSpacesInSingleArguments() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Samsung CLI \(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let java = root.appendingPathComponent("jdk/Contents/Home/bin/java")
        let libraries = root.appendingPathComponent("tools/ide/lib-ncli")
        try FileManager.default.createDirectory(at: java.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraries, withIntermediateDirectories: true)
        try Data().write(to: java)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: java.path)
        let jar = libraries.appendingPathComponent("cli core.jar")
        try Data().write(to: jar)
        let cli = root.appendingPathComponent("tools/ide/bin/tizen")
        let command = TizenCLI.invocation(cli, ["security-profiles", "list"])
        #expect(command.executable == java)
        let cp = try #require(command.arguments.firstIndex(of: "-cp"))
        #expect(command.arguments[cp + 1].contains(jar.path))
        #expect(command.arguments[cp + 2] == "org.tizen.ncli.ide.shell.Main")
        #expect(command.arguments.contains("security-profiles"))
        #expect(command.directory == cli.deletingLastPathComponent())
    }

    @Test func scriptedToolsRetainTheirOriginalInvocation() {
        let cli = URL(fileURLWithPath: "/nonexistent/sdk/tools/ide/bin/tizen")
        let command = TizenCLI.invocation(cli, ["security-profiles", "list"])
        #expect(command.executable == cli)
        #expect(command.arguments == ["security-profiles", "list"])
        #expect(command.directory == nil)
    }
}
