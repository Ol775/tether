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
}

public enum CertificateProfileError: LocalizedError, Equatable, Sendable {
    case invalidFile, configurationFailed
    public var errorDescription: String? {
        switch self {
        case .invalidFile: "Choose a valid profiles.xml containing a named signing profile. Import .p12 files using Samsung Certificate Manager."
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
