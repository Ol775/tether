import Foundation

/// The same validated target is used for port checks, pairing and connections.
public struct ConnectionEndpoint: Equatable, Sendable {
    public let host: String
    public let port: Int

    public init(address: String, port: String) throws {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = address.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { throw DeviceError.invalidHost }
        let host = String(parts[0])
        let portText = parts.count == 2 ? String(parts[1]) : port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !portText.isEmpty, portText.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(portText) else { throw DeviceError.invalidHost }
        _ = try DeviceManager.endpoint(host, number)
        self.host = host
        self.port = number
    }
}
