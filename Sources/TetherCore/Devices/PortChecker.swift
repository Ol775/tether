import Foundation
import Network

/// A TCP handshake only: does not pair, authenticate, or send a device command.
public enum PortChecker {
    public enum Result: Equatable, Sendable {
        case open, refused, timedOut, unreachable(String), cancelled
    }

    public static func check(_ endpoint: ConnectionEndpoint, timeout: TimeInterval = 4) async -> Result {
        let probe = Probe(endpoint: endpoint, timeout: timeout)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { probe.start($0) }
        } onCancel: {
            probe.cancel()
        }
    }

    // All mutable state is confined to queue, including timeout and cancellation races.
    private final class Probe: @unchecked Sendable {
        let queue = DispatchQueue(label: "tether.port-check")
        let connection: NWConnection
        let timeout: TimeInterval
        var continuation: CheckedContinuation<Result, Never>?
        var timer: DispatchWorkItem?
        var cancelled = false

        init(endpoint: ConnectionEndpoint, timeout: TimeInterval) {
            connection = NWConnection(host: NWEndpoint.Host(endpoint.host),
                                      port: NWEndpoint.Port(rawValue: UInt16(endpoint.port))!, using: .tcp)
            self.timeout = timeout
        }

        func start(_ continuation: CheckedContinuation<Result, Never>) {
            queue.async { [self] in
                self.continuation = continuation
                guard !cancelled else { finish(.cancelled); return }
                connection.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready: finish(.open)
                    case .failed(let error), .waiting(let error):
                        if case .posix(.ECONNREFUSED) = error { finish(.refused) }
                        else { finish(.unreachable(error.localizedDescription)) }
                    case .cancelled: finish(.cancelled)
                    default: break
                    }
                }
                let timer = DispatchWorkItem { [weak self] in self?.finish(.timedOut) }
                self.timer = timer
                queue.asyncAfter(deadline: .now() + max(0, timeout), execute: timer)
                connection.start(queue: queue)
            }
        }

        func cancel() {
            queue.async { [self] in
                cancelled = true
                finish(.cancelled)
            }
        }

        func finish(_ result: Result) {
            guard let continuation else { return }
            self.continuation = nil
            timer?.cancel()
            timer = nil
            connection.stateUpdateHandler = nil
            connection.cancel()
            continuation.resume(returning: result)
        }
    }
}
