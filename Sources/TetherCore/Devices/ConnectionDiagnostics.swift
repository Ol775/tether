import Foundation

public enum DebugService: String, CaseIterable, Codable, Sendable, Identifiable {
    case sdb, adb
    public var id: String { rawValue }
    public var title: String { self == .sdb ? "Samsung TV (SDB)" : "Android / Fire TV (ADB)" }
    public var defaultPort: String { self == .sdb ? "26101" : "5555" }
}

public struct DiagnosticCheck: Identifiable, Equatable, Sendable {
    public enum Status: String, Sendable { case passed, warning, failed }
    public let id: String
    public let title: String
    public let status: Status
    public let detail: String

    public init(id: String, title: String, status: Status, detail: String) {
        self.id = id; self.title = title; self.status = status; self.detail = detail
    }
}

public struct ConnectionReport: Sendable {
    public let service: DebugService
    public let endpoint: ConnectionEndpoint
    public let date: Date
    public let checks: [DiagnosticCheck]
    public let nextStep: String

    /// Only explicit check results are included. Never dump TV metadata, certificate files or environment variables.
    public var text: String {
        (["Tether connection diagnostics", date.ISO8601Format(), service.title,
          "Target: \(endpoint.host):\(endpoint.port)"] + checks.map {
            "[\($0.status.rawValue)] \($0.title): \($0.detail)"
        } + ["Next step: \(nextStep)"]).joined(separator: "\n")
    }
}

/// The TV's public status endpoint also exposes identifiers and tokens. Decode only connection-related fields.
public struct SamsungConnectionStatus: Decodable, Sendable {
    public let developerMode: String?
    public let developerIP: String?
    public let modelName: String?
    public let PowerState: String?
}

public enum ConnectionDiagnostics {
    private struct SamsungResponse: Decodable { let device: SamsungConnectionStatus }
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    public static func samsungStatus(host: String, session: URLSession = .shared) async throws -> SamsungConnectionStatus {
        _ = try DeviceManager.endpoint(host, 8001)
        var parts = URLComponents()
        parts.scheme = "http"; parts.host = host; parts.port = 8001; parts.path = "/api/v2/"
        guard let url = parts.url else { throw DeviceError.invalidHost }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request, delegate: NoRedirects())
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 65_536 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(SamsungResponse.self, from: data).device
    }

    public static func run(service: DebugService, endpoint: ConnectionEndpoint, localAddresses: [String],
                           adb: ADBRunner, sdb: SDBRunner,
                           probe: @Sendable (ConnectionEndpoint) async -> PortChecker.Result = { await PortChecker.check($0) },
                           status: @Sendable (String) async throws -> SamsungConnectionStatus = { try await samsungStatus(host: $0) },
                           progress: @Sendable (String) async -> Void = { _ in }) async throws -> ConnectionReport {
        var checks: [DiagnosticCheck] = []
        checks.append(.init(id: "mac", title: "Mac network addresses", status: localAddresses.isEmpty ? .warning : .passed,
                            detail: localAddresses.isEmpty ? "No active Wi-Fi or Ethernet IPv4 address found." : localAddresses.joined(separator: ", ")))
        await progress("Checking the debugging port…")
        let port = await probe(endpoint)
        try Task.checkCancellation()
        let portDetail: String
        switch port {
        case .open: portDetail = "TCP connection to \(endpoint.host):\(endpoint.port) succeeded. This does not yet confirm a debugging session."
        case .refused: portDetail = "The device answered but refused port \(endpoint.port). Check debugging and the port number."
        case .timedOut: portDetail = "No TCP response within four seconds. Check Wi-Fi, device power, VPN and access point client forwarding."
        case .unreachable(let reason): portDetail = "Could not reach the debugging port: \(reason)"
        case .cancelled: throw CancellationError()
        }
        checks.append(.init(id: "port", title: "Debugging port", status: port == .open ? .passed : .failed, detail: portDetail))

        var developerProblem = false
        var tvAnswered = false
        if service == .sdb {
            await progress("Reading Samsung Developer Mode status…")
            do {
                let info = try await status(endpoint.host)
                tvAnswered = true
                checks.append(.init(id: "tv", title: "Samsung network service", status: .passed,
                                    detail: "\(info.modelName ?? "Samsung TV") answered on port 8001. Power: \(info.PowerState ?? "not reported")."))
                let mode = info.developerMode
                let host = info.developerIP
                let modeOff = mode != nil && mode != "1"
                let hostMismatch = host != nil && !localAddresses.isEmpty && !localAddresses.contains(host!)
                developerProblem = modeOff || hostMismatch
                checks.append(.init(id: "developer", title: "Developer Mode and Host PC IP",
                                    status: developerProblem ? .failed : (mode == nil || host == nil || localAddresses.isEmpty ? .warning : .passed),
                                    detail: "Developer Mode: \(mode == "1" ? "on" : mode == nil ? "not reported" : "off"). Host PC IP: \(host ?? "not reported")."
                                    + (hostMismatch ? " This does not match an active Mac address." : "")))
            } catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                checks.append(.init(id: "tv", title: "Samsung network service", status: .warning,
                                    detail: "No readable Samsung status from port 8001. Some TVs do not expose this service; this alone does not prove the TV is offline."))
            }
        }

        await progress("Checking the \(service.rawValue.uppercased()) session…")
        var sessionReady = false
        var unauthorized = false
        do {
            let output = try await (service == .sdb ? sdb.run(["devices"], timeout: .seconds(6)) : adb.run(["devices"], timeout: .seconds(6)))
            let target = "\(endpoint.host):\(endpoint.port)"
            let rows = output.split(whereSeparator: \.isNewline).map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            let state = rows.first { $0.count >= 2 && $0[0] == target }?[1]
            unauthorized = state == "unauthorized"
            sessionReady = state == "device"
            checks.append(.init(id: "session", title: "\(service.rawValue.uppercased()) session", status: sessionReady ? .passed : .warning,
                                detail: state.map { "\(target) is listed as \($0)." } ?? "The local service responded, but this address is not connected. Diagnostics do not connect automatically."))
            if sessionReady && service == .sdb {
                let capability = try await sdb.run(["capability"], serial: target, timeout: .seconds(6))
                let values = TizenParsers.capability(capability)
                sessionReady = !values.isEmpty
                checks.append(.init(id: "profile", title: "TV capabilities", status: sessionReady ? .passed : .failed,
                                    detail: sessionReady ? "Readable TV profile. Tizen \(values["platform_version"] ?? "version not reported")." : "The TV did not return a readable profile."))
            }
        } catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            sessionReady = false
            let message: String
            switch error {
            case let e as SDBError: message = e.advice
            case let e as ADBError: message = e.advice
            default: message = error.localizedDescription
            }
            checks.append(.init(id: "service", title: "\(service.rawValue.uppercased()) service", status: .failed, detail: message))
        }
        try Task.checkCancellation()
        let next: String
        if sessionReady { next = "The debugging session is working. Return to your device in Tether." }
        else if developerProblem { next = "On the TV, enable Developer Mode and set Host PC IP to an active Mac address shown above, then fully restart the TV." }
        else if unauthorized { next = service == .adb ? "Accept the debugging authorisation prompt on the device, then reconnect. Wireless debugging may need pairing first." : "The TV has not authorised this Mac. Check the TV's Developer Mode Host PC IP and fully restart the TV." }
        else if port != .open {
            next = tvAnswered ? "The TV is reachable, but its debugging port is not. Check Developer Mode, the configured port and fully restart the TV."
                : "Check the TV's network connection and local network permissions. If other Wi-Fi clients are also unreachable, check the access point before changing debugging settings."
        } else { next = "The port is reachable, but no working debugging session was confirmed. Restart the \(service.rawValue.uppercased()) service below, then reconnect. If it still fails, check device authorisation." }
        return ConnectionReport(service: service, endpoint: endpoint, date: Date(), checks: checks, nextStep: next)
    }
}
