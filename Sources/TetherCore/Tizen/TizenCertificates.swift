import Foundation

public enum CertificateState: Equatable, Sendable {
    case ready, missing, notForThisTV, toolsMissing, checkFailed
    /// A profile exists but the tools don't show which TVs it covers.
    case unknown

    public var advice: String {
        switch self {
        case .ready: "Certificate ready for this TV."
        case .missing: "No Samsung certificate yet. Open Certificate Manager from the Samsung tools, create a Samsung certificate and add this TV to it."
        case .notForThisTV: "Your certificate doesn't include this TV. Add the TV in Certificate Manager and regenerate the certificate."
        case .toolsMissing: "Set up the Samsung tools first."
        case .unknown: "A signing profile is available. Samsung will check whether the signed package includes this TV when you install it."
        case .checkFailed: "Tether couldn't read the signing profiles. Open certificate setup to check the Samsung tools and try again."
        }
    }
}

/// Reads, never creates: Samsung certificate creation is guided through Samsung's own Certificate Manager
/// (whether it can be scripted without a Samsung sign-in is unresolved until tried on hardware).
public struct TizenCertificates: Sendable {
    private let tools: SamsungTools

    public init(tools: SamsungTools) { self.tools = tools }

    public func state(for device: TizenDevice) async -> CertificateState {
        guard let cli = tools.tizenCLI else { return .toolsMissing }
        guard let r = try? await TizenCLI.run(cli, ["security-profiles", "list"]), r.status == 0 else { return .checkFailed }
        let lines = r.out.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        // Tizen Studio prints a Loaded-in path and a Name table, even when there are no profiles.
        let profiles = lines.filter {
            let lower = $0.lowercased()
            return !$0.allSatisfy({ $0 == "=" || $0 == "-" }) && lower != "name"
                && !lower.hasPrefix("loaded in") && !lower.hasPrefix("current active profile:")
                && !lower.hasPrefix("no ") && !lower.hasPrefix("duid:")
                && !lower.hasPrefix("[profile name]")
        }
        guard !profiles.isEmpty else { return .missing }
        let ids = lines.filter { $0.lowercased().hasPrefix("duid:") }
            .flatMap { $0.dropFirst(5).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        if ids.isEmpty || device.deviceID == device.serial { return .unknown }
        return ids.contains(device.deviceID) ? .ready : .notForThisTV
    }

    /// Jellyfin builds sign with `package -s <name>` but `install-permit` uses the SDK's active profile, so the two must agree.
    /// The active profile is only compared when the CLI reports one; an unreported one is left to Samsung's own install check.
    public func checkProfile(named name: String) async throws {
        guard let cli = tools.tizenCLI else { throw SDBError.toolsMissing }
        guard let r = try? await TizenCLI.run(cli, ["security-profiles", "list"]), r.status == 0 else { throw CertificateProfileError.unreadable }
        let lines = r.out.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.contains(where: { $0 == name || $0.hasPrefix(name + " ") }) else { throw CertificateProfileError.profileNotFound(name) }
        if let active = lines.first(where: { $0.lowercased().hasPrefix("current active profile:") })?
            .dropFirst("current active profile:".count).trimmingCharacters(in: .whitespaces),
           !active.isEmpty, active != name { throw CertificateProfileError.notActive(name, active: active) }
    }

    /// Registers the user's existing profile file; certificate keys and passwords stay in Samsung's files.
    public func useProfilesFile(_ file: URL) async throws {
        guard let cli = tools.tizenCLI else { throw SDBError.toolsMissing }
        let data = try Data(contentsOf: file)
        guard Self.containsProfiles(data) else { throw CertificateProfileError.invalidFile }
        let result = try await TizenCLI.run(cli, ["cli-config", "-g", "default.profiles.path=\(file.path)"])
        guard result.status == 0 else { throw CertificateProfileError.configurationFailed }
    }

    static func containsProfiles(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8),
              text.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil else { return false }
        let reader = ProfileReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        return parser.parse() && reader.hasProfile
    }

    /// The active signing profile's certificate files: author and distributor `.p12`, and the
    /// `device-profile.xml` beside the author key (used for native install-permit). Nil if no profiles file
    /// or active profile with both keys. Native signing and native permit both key off these.
    public func activeProfileFiles() -> ProfileFiles? {
        guard let data = try? Data(contentsOf: tools.profilesFile) else { return nil }
        let reader = ProfileFilesReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), let author = reader.author, let distributor = reader.distributor else { return nil }
        let authorURL = URL(fileURLWithPath: author)
        return ProfileFiles(author: authorURL,
                            distributor: URL(fileURLWithPath: distributor),
                            deviceProfile: authorURL.deletingLastPathComponent().appendingPathComponent("device-profile.xml"))
    }
}

public struct ProfileFiles: Sendable {
    public let author: URL
    public let distributor: URL
    public let deviceProfile: URL
}

/// Reads the active profile's author (distributor="0") and distributor (distributor="1") key paths.
private final class ProfileFilesReader: NSObject, XMLParserDelegate {
    private var active: String?
    private var inActive = false
    var author: String?
    var distributor: String?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        switch elementName {
        case "profiles": active = a["active"]
        case "profile": inActive = a["name"] != nil && a["name"] == active
        case "profileitem" where inActive:
            guard let key = a["key"], !key.isEmpty else { return }
            if a["distributor"] == "0" { author = key } else if a["distributor"] == "1" { distributor = key }
        default: break
        }
    }
}

public enum CertificateProfileError: LocalizedError, Equatable, Sendable {
    case invalidFile, configurationFailed, unreadable, profileNotFound(String), notActive(String, active: String)
    public var errorDescription: String? {
        switch self {
        case .invalidFile: "Choose a valid profiles.xml containing a named signing profile. Import .p12 files using Samsung Certificate Manager."
        case .unreadable: "Tether couldn't read the Samsung signing profiles. Open certificate setup and check the Samsung tools."
        case .profileNotFound(let name): "No Samsung signing profile named “\(name)” exists. Check the name in Certificate Manager."
        case .notActive(let name, let active): "“\(name)” is not the active Samsung profile (“\(active)”). Make it active in Certificate Manager so installation uses the same certificate."
        case .configurationFailed: "Samsung's tools couldn't select that profile file. Check it in Certificate Manager, then try again."
        }
    }
}

private final class ProfileReader: NSObject, XMLParserDelegate {
    var hasProfile = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if elementName == "profile", let name = attributes["name"], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasProfile = true
        }
    }

}
