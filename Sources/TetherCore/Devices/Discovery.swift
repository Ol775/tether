import Foundation
import Network

public struct DiscoveredEndpoint: Hashable, Sendable {
    public enum Kind: Sendable { case connect, pairing }
    public let host: String
    public let port: Int
    public let kind: Kind
    public let name: String
}

/// Bonjour discovery of wireless-debugging devices. Manual-tested (see docs/device-checklist.md).
/// Resolving a service briefly opens a TCP connection to it, then drops it.
public enum Discovery {
    public static func stream() -> AsyncStream<DiscoveredEndpoint> {
        AsyncStream { continuation in
            let queue = DispatchQueue(label: "tether.discovery")
            let services: [(String, DiscoveredEndpoint.Kind)] = [("_adb-tls-connect._tcp", .connect), ("_adb-tls-pairing._tcp", .pairing)]
            let browsers = services.map { type, kind in
                let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
                browser.browseResultsChangedHandler = { _, changes in
                    for case .added(let result) in changes {
                        guard case .service(let name, _, _, _) = result.endpoint else { continue }
                        resolve(result.endpoint, queue: queue) { host, port in
                            continuation.yield(.init(host: host, port: port, kind: kind, name: name))
                        }
                    }
                }
                browser.start(queue: queue)
                return browser
            }
            let held = browsers
            continuation.onTermination = { _ in held.forEach { $0.cancel() } }
        }
    }

    private static func resolve(_ endpoint: NWEndpoint, queue: DispatchQueue, _ done: @escaping @Sendable (String, Int) -> Void) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if case .hostPort(.ipv4(let address), let port)? = connection.currentPath?.remoteEndpoint {
                    done("\(address)".split(separator: "%")[0].description, Int(port.rawValue))
                }
                connection.cancel()
            case .failed: connection.cancel()
            default: break
            }
        }
        connection.start(queue: queue)
    }
}
