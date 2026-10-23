import Foundation

public enum CertificateState: Equatable, Sendable {
    case ready, missing, notForThisTV, toolsMissing
    /// A profile exists but the tools don't show which TVs it covers.
    case unknown

    public var advice: String {
        switch self {
        case .ready: "Certificate ready for this TV."
        case .missing: "No Samsung certificate yet. Open Certificate Manager from the Samsung tools, create a Samsung certificate and add this TV to it."
        case .notForThisTV: "Your certificate doesn't include this TV. Add the TV in Certificate Manager and regenerate the certificate."
        case .toolsMissing: "Set up the Samsung tools first."
        case .unknown: "A certificate exists, but Tether can't tell whether it includes this TV. If an install fails with a certificate error, add the TV in Certificate Manager."
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
        guard let r = try? await ProcessRunner.run(cli, ["security-profiles", "list"], timeout: .seconds(30)), r.status == 0 else { return .missing }
        // Output format is assumed (see the tests); lines that don't fit are ignored.
        let lines = r.out.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard !lines.isEmpty else { return .missing }
        let ids = lines.filter { $0.lowercased().hasPrefix("duid:") }
            .flatMap { $0.dropFirst(5).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        if ids.isEmpty { return .unknown }
        return ids.contains(device.deviceID) ? .ready : .notForThisTV
    }
}
