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
        let out = try await sdb.run(["connect", target])
        // sdb connect can exit 0 and still say it failed; the verdict is in the text.
        guard out.contains("connected to"), !out.contains("failed") else { throw SDBError.classify(code: 1, output: out) }
        // Developer Mode off, a wrong host IP on the TV or a blocked model can all still print "connected": require the TV
        // to be listed as ready and to tell us what it is.
        guard let listed = TizenParsers.devices(try await sdb.run(["devices"])).first(where: { $0.serial == target }) else { throw SDBError.notConnected }
        guard listed.state == "device" else { throw listed.state == "unauthorized" ? SDBError.developerModeOff : SDBError.notConnected }
        let capability = TizenParsers.capability(try await sdb.run(["capability"], serial: target))
        guard capability["model_name"] != nil else { throw SDBError.commandFailed(code: 0, output: "The TV connected but didn't report its model.") }
        let device = TizenParsers.device(serial: target, capability: capability)
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
            let device = try await profile(serial: d.serial)
            if (device.modelYear ?? Self.oldestSupportedYear) >= Self.oldestSupportedYear { result.append(device) }
        }
        return result
    }

    public func profile(serial: String) async throws -> TizenDevice {
        TizenParsers.device(serial: serial, capability: TizenParsers.capability(try await sdb.run(["capability"], serial: serial)))
    }
}
