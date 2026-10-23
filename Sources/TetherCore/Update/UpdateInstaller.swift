import CryptoKit
import Foundation

/// Downloads a release and installs nothing until it passes every check: asset URL and redirects stay on GitHub, size cap,
/// the Ed25519 release signature (version-bound), SHA-256, bundle id and version, and the app's code signature.
public struct UpdateInstaller: Sendable {
    private let workDir: URL
    private let session: URLSession
    private let publicKey: String
    private let maxBytes: Int64
    private let bundleID: String

    public init(workDir: URL, session: URLSession = .shared, publicKey: String = Updater.publicKey, maxBytes: Int64 = 100_000_000, bundleID: String = "io.github.ol775.tether") {
        self.workDir = workDir
        self.session = session
        self.publicKey = publicKey
        self.maxBytes = maxBytes
        self.bundleID = bundleID
    }

    /// Follows a redirect only to https on GitHub's own hosts; otherwise the 3xx comes back and the download fails.
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(request.url?.scheme == "https" && Updater.isAllowedRedirectHost(request.url?.host) ? request : nil)
        }
    }

    private static func sha256(of url: URL) -> String? {
        guard let d = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    /// Returns the verified `Tether.app`, unpacked inside the work folder. Anything that fails a check is deleted.
    public func prepare(_ info: UpdateInfo, progress: @Sendable (String) -> Void) async throws -> URL {
        guard let zipURL = info.zipURL, Updater.isTrustedAsset(zipURL) else { throw UpdateError.noDownload }
        guard let want = info.sha256, !want.isEmpty, let sigURL = info.sigURL, Updater.isTrustedAsset(sigURL) else { throw UpdateError.notSigned }

        let fm = FileManager.default
        let root = workDir.appendingPathComponent("update-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var keep = false
        defer { if !keep { try? fm.removeItem(at: root) } }

        progress("Downloading version \(info.version)…")
        let zip = root.appendingPathComponent("update.zip")
        let (temp, response) = try await download(zipURL)
        defer { try? fm.removeItem(at: temp) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.downloadFailed }
        let size = (try? fm.attributesOfItem(atPath: temp.path)[.size] as? Int64) ?? Int64.max
        guard size <= maxBytes, response.expectedContentLength <= maxBytes else { throw UpdateError.tooLarge }
        try fm.moveItem(at: temp, to: zip)

        progress("Verifying…")
        let zipData = try Data(contentsOf: zip, options: .mappedIfSafe)
        guard let sig = await fetchSignature(sigURL),
              Updater.verifySignature(Updater.signedMessage(version: info.version, zip: zipData), base64Signature: sig, publicKey: publicKey)
        else { throw UpdateError.badSignature }
        guard Self.sha256(of: zip) == want.lowercased() else { throw UpdateError.badChecksum }

        progress("Unpacking…")
        guard Self.sha256(of: zip) == want.lowercased() else { throw UpdateError.changedAfterCheck }   // closes the gap between checking and unpacking
        let out = root.appendingPathComponent("out")
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        guard let unzip = try? await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", zip.path, out.path], timeout: .seconds(120)), unzip.status == 0
        else { throw UpdateError.unzipFailed }
        let app = out.appendingPathComponent("Tether.app")
        let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard plist?["CFBundleIdentifier"] as? String == bundleID else { throw UpdateError.notTether }
        guard plist?["CFBundleShortVersionString"] as? String == info.version else { throw UpdateError.wrongVersion }
        guard try await codesignOK(app) else { throw UpdateError.badCodeSignature }

        try? fm.removeItem(at: zip)   // the verified app is all that's kept
        keep = true
        return app
    }

    private func download(_ url: URL) async throws -> (URL, URLResponse) {
        do { return try await session.download(from: url, delegate: RedirectGuard()) }
        catch { throw UpdateError.downloadFailed }
    }

    private func fetchSignature(_ url: URL) async -> String? {
        guard let (data, response) = try? await session.data(from: url, delegate: RedirectGuard()),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count < 10_000 else { return nil }   // a signature is ~90 bytes
        return String(data: data, encoding: .utf8)
    }

    private func codesignOK(_ app: URL) async throws -> Bool {
        let r = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/codesign"), ["--verify", "--deep", "--strict", app.path], timeout: .seconds(60))
        return r.status == 0
    }

    /// False for a translocated copy (a quarantined app run straight from Downloads, mounted read-only) or a folder we can't write to.
    public static func canReplace(_ dest: URL) -> Bool {
        dest.pathExtension == "app" && !dest.path.contains("/AppTranslocation/")
            && FileManager.default.isWritableFile(atPath: dest.deletingLastPathComponent().path)
    }

    /// Hands a verified app to a helper that waits for this process to quit, swaps it in (keeping the old one as a backup) and
    /// relaunches. Returns once the hand-off has started; the caller should then quit.
    public func apply(_ app: URL, to dest: URL, relaunch: Bool = true, waitingForPID pid: Int32 = ProcessInfo.processInfo.processIdentifier) throws {
        let fm = FileManager.default
        let inside = app.resolvingSymlinksInPath().path.hasPrefix(workDir.resolvingSymlinksInPath().path + "/")
        guard fm.fileExists(atPath: app.path), inside, dest.pathExtension == "app" else { throw UpdateError.failedFinalCheck }
        let check = Process(); check.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); check.arguments = ["--verify", "--deep", "--strict", app.path]
        check.standardOutput = FileHandle.nullDevice; check.standardError = FileHandle.nullDevice
        try check.run(); check.waitUntilExit()
        guard check.terminationStatus == 0 else { throw UpdateError.failedFinalCheck }

        let backup = workDir.appendingPathComponent("previous/Tether.app")
        try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let script = app.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("swap.sh")
        let body = """
        #!/bin/zsh
        # waits for the running app to quit, swaps in the new build (keeping the old one as a backup), then relaunches
        PID="$1"; NEW="$2"; DEST="$3"; BACKUP="$4"; RELAUNCH="$5"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        rm -rf "$BACKUP"
        [ -d "$DEST" ] && mv "$DEST" "$BACKUP"
        if cp -R "$NEW" "$DEST"; then
          [ "$RELAUNCH" = "1" ] && open "$DEST"
        else
          [ -d "$BACKUP" ] && mv "$BACKUP" "$DEST"
          [ "$RELAUNCH" = "1" ] && open "$DEST"
        fi
        exit 0
        """
        do { try body.write(to: script, atomically: true, encoding: .utf8) } catch { throw UpdateError.cannotStartInstaller }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [script.path, String(pid), app.path, dest.path, backup.path, relaunch ? "1" : "0"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { throw UpdateError.cannotStartInstaller }
    }
}
