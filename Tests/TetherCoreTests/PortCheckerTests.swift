import Darwin
import Foundation
import Testing
@testable import TetherCore

struct PortCheckerTests {
    /// Ask the OS for an available loopback port and open a listener on it.
    private func listener() throws -> (Int32, ConnectionEndpoint) {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            Darwin.close(fd)
            throw error
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0, Darwin.listen(fd, 8) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            Darwin.close(fd)
            throw error
        }
        return (fd, try ConnectionEndpoint(address: "127.0.0.1", port: String(UInt16(bigEndian: address.sin_port))))
    }

    @Test func detectsListeningPort() async throws {
        let (fd, endpoint) = try listener()
        defer { Darwin.close(fd) }
        let result = await PortChecker.check(endpoint)
        #expect(result == .open)
    }

    @Test func detectsRefusedPort() async throws {
        let (fd, endpoint) = try listener()
        // A bound socket that has never listened can silently drop connection attempts on macOS.
        // Close the listener so this fixture exercises a closed port instead of a timeout.
        #expect(Darwin.close(fd) == 0)
        let result = await PortChecker.check(endpoint)
        #expect(result == .refused)
    }

    @Test func deadlineCompletes() async throws {
        let endpoint = try ConnectionEndpoint(address: "127.0.0.1", port: "9")
        #expect(await PortChecker.check(endpoint, timeout: 0) == .timedOut)
    }

    @Test func alreadyCancelledCheckCompletes() async throws {
        let endpoint = try ConnectionEndpoint(address: "127.0.0.1", port: "9")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await PortChecker.check(endpoint)
        }
        #expect(await task.value == .cancelled)
    }
}
