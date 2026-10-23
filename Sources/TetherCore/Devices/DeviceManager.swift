import Foundation

public enum DeviceError: Error, Equatable, Sendable {
    case invalidHost, invalidPairingCode
}

public actor DeviceManager {
    private let adb: ADBRunner

    public init(adb: ADBRunner) { self.adb = adb }

    public func connect(host: String, port: Int = 5555) async throws {
        let target = try Self.endpoint(host, port)
        let out = try await adb.run(["connect", target])
        // adb connect exits 0 even on failure; the verdict is in the text.
        if out.contains("connected to") { return }
        throw ADBError.classify(code: 1, output: out)
    }

    public func pair(host: String, port: Int, code: String) async throws {
        let target = try Self.endpoint(host, port)
        guard code.count == 6, code.allSatisfy(\.isASCII), code.allSatisfy(\.isNumber) else { throw DeviceError.invalidPairingCode }
        let out = try await adb.run(["pair", target, code])
        if out.contains("Successfully paired") { return }
        throw ADBError.classify(code: 1, output: out)
    }

    public func disconnect(serial: String) async throws {
        _ = try await adb.run(["disconnect", serial])
    }

    /// Ready devices only; unauthorized/offline entries are skipped.
    public func devices() async throws -> [DeviceProfile] {
        let listed = Parsers.devices(try await adb.run(["devices", "-l"]))
        var result: [DeviceProfile] = []
        for d in listed where d.state == "device" {
            result.append(try await profile(serial: d.serial))
        }
        return result
    }

    public func profile(serial: String) async throws -> DeviceProfile {
        Parsers.profile(serial: serial, getprop: try await adb.run(["shell", "getprop"], serial: serial))
    }

    static func endpoint(_ host: String, _ port: Int) throws -> String {
        let ok = !host.isEmpty && host.count <= 253 && !host.hasPrefix("-")
            && host.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0) || $0 == "." || $0 == "-") }
        guard ok, (1...65535).contains(port) else { throw DeviceError.invalidHost }
        return "\(host):\(port)"
    }
}
