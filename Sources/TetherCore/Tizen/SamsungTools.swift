import CryptoKit
import Foundation

public enum SamsungToolsError: Error, Equatable, Sendable {
    case licenseNotAccepted
    case insecureURL
    case downloadFailed(status: Int)
    case checksumMismatch
    case installerFailed(code: Int32, output: String)
    case toolsMissingAfterInstall

    public var advice: String {
        switch self {
        case .licenseNotAccepted: "Read and accept Samsung's licence to download their tools."
        case .insecureURL: "The download address isn't secure, so Tether refused it."
        case .downloadFailed(let status): "Samsung's download server answered \(status). Try again later."
        case .checksumMismatch: "The download didn't match the installer Tether expects, so it was not run. Samsung may have changed it; check for a Tether update."
        case .installerFailed(_, let output): output.isEmpty ? "Samsung's installer failed." : "Samsung's installer failed: \(output)"
        case .toolsMissingAfterInstall: "The installer finished but sdb wasn't found. Try again."
        }
    }
}

/// Fetches Samsung's official command-line tools on first use. Tether never bundles or redistributes them;
/// the user accepts Samsung's licence and the installer runs from `<home>/tizen-studio`.
public actor SamsungTools {
    public static let defaultInstallerURL = URL(string: "https://download.tizen.org/sdk/Installer/tizen-studio_6.0/web-cli_Tizen_Studio_6.0_macos-64.bin")!

    /// SHA-256 of that exact file (277,146,828 bytes, Last-Modified 2024-11-01), taken when this was written.
    /// Samsung publishes no checksum, so this pins what was seen then; a changed file is refused, not run.
    public static let defaultInstallerSHA256 = "3205597d127c4b93d924f591153b0b2f83f4ab90c4abc8786b3e902397e5488e"

    private let home: URL
    private let session: URLSession
    private let installerURL: URL
    private let expectedSHA256: String

    public init(home: URL, session: URLSession = .shared, installerURL: URL = SamsungTools.defaultInstallerURL,
                expectedSHA256: String = SamsungTools.defaultInstallerSHA256) {
        self.home = home
        self.session = session
        self.installerURL = installerURL
        self.expectedSHA256 = expectedSHA256.lowercased()
    }

    private nonisolated var root: URL { home.appendingPathComponent("tizen-studio") }
    private nonisolated var marker: URL { home.appendingPathComponent(".incomplete") }

    public nonisolated var sdb: URL? { executable("tools/sdb") }
    public nonisolated var tizenCLI: URL? { executable("tools/ide/bin/tizen") }
    public nonisolated var certificateManager: URL? {
        let app = root.appendingPathComponent("tools/certificate-manager/Certificate-manager.app")
        return Bundle(url: app)?.executableURL != nil ? app : nil
    }
    /// The GUI wrapper has the same unquoted-Java-path bug as the CLI launcher.
    public nonisolated func startPackageManager() throws -> Process {
        let java = root.appendingPathComponent("jdk/Contents/Home/bin/java")
        let directory = root.appendingPathComponent("package-manager")
        let jar = directory.appendingPathComponent("PackageManagerV2.jar")
        guard FileManager.default.isExecutableFile(atPath: java.path),
              FileManager.default.fileExists(atPath: jar.path) else { throw CocoaError(.fileNoSuchFile) }
        let process = Process()
        process.executableURL = java
        process.arguments = ["-XX:+IgnoreUnrecognizedVMOptions", "-XstartOnFirstThread", "-jar", jar.path, "-path", directory.path]
        process.currentDirectoryURL = directory
        let logURL = home.appendingPathComponent("package-manager-launch.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        process.standardOutput = log
        process.standardError = log
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { _ in try? log.close() }
        try process.run()
        return process
    }
    /// A leftover marker means an earlier run never finished, so nothing under the folder is trusted.
    public nonisolated var isInstalled: Bool { !FileManager.default.fileExists(atPath: marker.path) && sdb != nil && tizenCLI != nil }

    private nonisolated func executable(_ path: String) -> URL? {
        guard !FileManager.default.fileExists(atPath: marker.path) else { return nil }
        let url = root.appendingPathComponent(path)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    public func install(acceptingLicense: Bool, progress: @Sendable (String) -> Void) async throws {
        guard acceptingLicense else { throw SamsungToolsError.licenseNotAccepted }
        guard installerURL.scheme == "https" else { throw SamsungToolsError.insecureURL }

        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data().write(to: marker)
        try? FileManager.default.removeItem(at: root)   // never build on a half-finished earlier run
        do {
            progress("Downloading Samsung's tools…")
            let (temp, response) = try await session.download(from: installerURL, delegate: SameHostHTTPSRedirects())
            defer { try? FileManager.default.removeItem(at: temp) }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw SamsungToolsError.downloadFailed(status: status) }
            let digest = SHA256.hash(data: try Data(contentsOf: temp, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
            guard digest == expectedSHA256 else { throw SamsungToolsError.checksumMismatch }   // before it is made executable or run
            progress("Downloaded and verified (sha256 \(digest.prefix(16))…). Running Samsung's installer…")

            let installer = home.appendingPathComponent("installer-\(UUID().uuidString).bin")
            defer { try? FileManager.default.removeItem(at: installer) }
            try FileManager.default.moveItem(at: temp, to: installer)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installer.path)
            try await run(installer, ["--accept-license", root.path])

            progress("Adding the certificate add-on…")
            let pm = root.appendingPathComponent("package-manager/package-manager-cli.bin")
            // Needed for installs on Samsung TVs; sdb listing and removal work without it, so a failure here is reported, not fatal.
            do { try await run(pm, ["install", "--accept-license", "cert-add-on"]) }
            catch { progress("The certificate add-on didn't install (\(error)). Installs on the TV may need Samsung's Certificate Manager.") }

            guard FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("tools/sdb").path) else { throw SamsungToolsError.toolsMissingAfterInstall }
            try FileManager.default.removeItem(at: marker)
            progress("Samsung tools are ready.")
        } catch {
            try? FileManager.default.removeItem(at: root)   // marker stays until a clean run
            throw error
        }
    }

    private func run(_ exe: URL, _ args: [String]) async throws {
        let r = try await ProcessRunner.run(exe, args, timeout: .seconds(1800))
        guard r.status == 0 else {
            throw SamsungToolsError.installerFailed(code: r.status, output: (r.err + r.out).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// Follows a redirect only when it stays on the same host over https; otherwise the 3xx comes back and the
/// download is reported as failed. Without this, https validation of the first URL says nothing about the last.
private final class SameHostHTTPSRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let ok = request.url?.scheme == "https" && request.url?.host == task.originalRequest?.url?.host
        completionHandler(ok ? request : nil)
    }
}
