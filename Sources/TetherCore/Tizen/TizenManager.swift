import Foundation

public enum TizenError: Error, Equatable, Sendable {
    case unsupportedModel(year: Int)
    case unsafeValue
    case lockedBySamsung(TizenAppID)
    case nothingToDo
    case wrongDevice
    case busy

    public var advice: String {
        switch self {
        case .unsupportedModel(let year): "This TV is from \(year). Tether supports Samsung TVs from 2019 onwards."
        case .unsafeValue: "That value isn't allowed."
        case .lockedBySamsung(let id): "Samsung's firmware won't let this TV remove \(id). It is locked, so Tether leaves it alone."
        case .nothingToDo: "Nothing to do."
        case .wrongDevice: "That restore point belongs to a different TV."
        case .busy: "Another change is still running on this TV. Wait for it to finish."
        }
    }
}

public actor TizenManager {
    private let sdb: SDBRunner
    static let oldestSupportedYear = 2019

    public init(sdb: SDBRunner) { self.sdb = sdb }

    public func connect(host: String, port: Int = 26101) async throws {
        let target = try DeviceManager.endpoint(host, port)
        var connectOutput = ""
        var connectError: (any Error)?
        do { connectOutput = try await sdb.run(["connect", target]) }
        catch { connectError = error }
        // Some retail TVs register successfully while `sdb connect` still prints a failure (or exits nonzero).
        // Only a ready device plus a readable profile confirms the session.
        let devices: [(serial: String, state: String, model: String?)]
        do { devices = TizenParsers.devices(try await sdb.run(["devices"])) }
        catch { throw connectError ?? error }
        guard let listed = devices.first(where: { $0.serial == target }) else {
            if let connectError { throw connectError }
            if !connectOutput.contains("connected to") || connectOutput.contains("failed") {
                throw SDBError.classify(code: 1, output: connectOutput)
            }
            throw SDBError.notConnected
        }
        guard listed.state == "device" else { throw listed.state == "unauthorized" ? SDBError.developerModeOff : SDBError.notConnected }
        let device = try await profile(serial: target, listedModel: listed.model)
        if let year = device.modelYear, year < Self.oldestSupportedYear {
            _ = try? await sdb.run(["disconnect", target])
            throw TizenError.unsupportedModel(year: year)
        }
    }

    public func disconnect(serial: String) async throws {
        _ = try await sdb.run(["disconnect", serial])
    }

    /// Ready, supported TVs only.
    public func devices() async throws -> [TizenDevice] {
        var result: [TizenDevice] = []
        for d in TizenParsers.devices(try await sdb.run(["devices"])) where d.state == "device" {
            let device = try await profile(serial: d.serial, listedModel: d.model)
            if (device.modelYear ?? Self.oldestSupportedYear) >= Self.oldestSupportedYear { result.append(device) }
        }
        return result
    }

    public func profile(serial: String) async throws -> TizenDevice {
        let listed = TizenParsers.devices(try await sdb.run(["devices"]))
            .first { $0.serial == serial && $0.state == "device" }
        return try await profile(serial: serial, listedModel: listed?.model)
    }

    private func profile(serial: String, listedModel: String?) async throws -> TizenDevice {
        var capability = TizenParsers.capability(try await sdb.run(["capability"], serial: serial))
        guard !capability.isEmpty else {
            throw SDBError.commandFailed(code: 0, output: "The TV connected but didn't report its capabilities.")
        }
        // Retail TVs can report the model only in `sdb devices`, not in `sdb capability`.
        if capability["model_name", default: ""].isEmpty, let listedModel {
            capability["model_name"] = listedModel
        }
        guard !capability["model_name", default: ""].isEmpty else {
            throw SDBError.commandFailed(code: 0, output: "The TV connected but didn't report its model.")
        }
        return TizenParsers.device(serial: serial, capability: capability)
    }
}
