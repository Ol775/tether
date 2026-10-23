import CryptoKit
import Foundation

public enum SamsungToolsError: Error, Equatable, Sendable {
    case licenseNotAccepted
    case insecureURL
    case downloadFailed(status: Int)
    case installerFailed(code: Int32, output: String)
    case toolsMissingAfterInstall

    public var advice: String {
        switch self {
        case .licenseNotAccepted: "Read and accept Samsung's licence to download their tools."
        case .insecureURL: "The download address isn't secure, so Tether refused it."
        case .downloadFailed(let status): "Samsung's download server answered \(status). Try again later."
        case .installerFailed(_, let output): output.isEmpty ? "Samsung's installer failed." : "Samsung's installer failed: \(output)"
        case .toolsMissingAfterInstall: "The installer finished but sdb wasn't found. Try again."
        }
    }
}

/// Fetches Samsung's official command-line tools on first use. Tether never bundles or redistributes them;
/// the user accepts Samsung's licence and the installer runs from `<home>/tizen-studio`.
public actor SamsungTools {
    public static let defaultInstallerURL = URL(string: "https://download.tizen.org/sdk/Installer/tizen-studio_6.0/web-cli_Tizen_Studio_6.0_macos-64.bin")!

    private let home: URL
    private let session: URLSession
    private let installerURL: URL

    public init(home: URL, session: URLSession = .shared, installerURL: URL = SamsungTools.defaultInstallerURL) {
        self.home = home
        self.session = session
        self.installerURL = installerURL
    }

    private nonisolated var root: URL { home.appendingPathComponent("tizen-studio") }
    private nonisolated var marker: URL { home.appendingPathComponent(".incomplete") }

    public nonisolated var sdb: URL? { executable("tools/sdb") }
    public nonisolated var tizenCLI: URL? { executable("tools/ide/bin/tizen") }
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
            let (temp, response) = try await session.download(from: installerURL)
            defer { try? FileManager.default.removeItem(at: temp) }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw SamsungToolsError.downloadFailed(status: status) }
            let digest = SHA256.hash(data: try Data(contentsOf: temp, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
            progress("Downloaded (sha256 \(digest.prefix(16))…). Running Samsung's installer…")

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
