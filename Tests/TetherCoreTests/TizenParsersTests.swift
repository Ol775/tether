import Foundation
import Testing
@testable import TetherCore

struct TizenParsersTests {
    @Test(arguments: [("QN65Q80TAFXZA", 2020), ("UE50RU7100", 2019), ("UE50RU7100KXXU", 2019), ("UE43AU9007KXXU", 2021), ("UN55NU8000FXZA", 2018), ("QE55Q80BAT", 2022), ("UN55NU8000", 2018), ("QE55Q80AAT", 2021), ("QE65QN90CATXXU", 2023)])
    func yearFromModelCode(code: String, year: Int) {
        #expect(TizenParsers.modelYear(fromModelCode: code) == year)
    }

    @Test func unknownModelCodeHasNoYear() {
        #expect(TizenParsers.modelYear(fromModelCode: "garbage") == nil)
        #expect(TizenParsers.modelYear(fromModelCode: "") == nil)
    }

    @Test func devicesParseState() {
        let list = TizenParsers.devices(fixture("sdb-devices.txt"))
        #expect(list.map(\.serial) == ["192.168.1.60:26101", "192.168.1.61:26101", "192.168.1.62:26101"])
        #expect(list.map(\.state) == ["device", "offline", "unauthorized"])
        #expect(list.map(\.model) == ["QE55Q80AAT", "UE50RU7100", "X"])
        #expect(TizenParsers.devices("192.168.1.60:26101 device").first?.model == nil)
    }

    @Test func deviceIDPrefersDUIDOverSerial() {
        let d = TizenParsers.device(serial: "192.168.1.60:26101", capability: TizenParsers.capability(fixture("sdb-capability-2021.txt")))
        #expect(d.deviceID == "DUIDTESTVALUE123" && d.model == "QE55Q80AAT" && d.modelYear == 2021)
        #expect(d.tizenVersion == "6.0" && !d.shellEnabled && !d.rootAvailable)
    }

    @Test func emptyOrPlaceholderIDsFallBackToSerial() {
        let d = TizenParsers.device(serial: "192.168.1.62:26101", capability: TizenParsers.capability(fixture("sdb-capability-2019.txt")))
        #expect(d.deviceID == "192.168.1.62:26101" && d.shellEnabled && d.modelYear == 2019)
        let junk = TizenParsers.device(serial: "s:1", capability: ["duid": "unknown", "model_name": "QE55Q80AAT"])
        #expect(junk.deviceID == "s:1")
    }

    @Test func hostileAppIDsAreRejected() {
        for bad in ["a;rm", "../x", "", String(repeating: "a", count: 129), "has space", "x`y`", "a$(b)", ".", "..", ".hidden", "-rf", "--help"] {
            #expect(TizenAppID(bad) == nil, "\(bad)")
        }
        #expect(TizenAppID("AprZAARz4r.Jellyfin") != nil && TizenAppID("org.tizen.smarthub") != nil)
    }

    @Test func appListParsesAndDropsHostileLines() {
        let apps = TizenParsers.apps(fixture("sdb-applist.txt"))
        #expect(apps.map(\.id.value) == ["org.example.netflix", "org.example.prime", "org.tizen.smarthub", "AprZAARz4r.Jellyfin"])
        #expect(apps.first?.name == "Netflix" && apps[1].name == "Prime Video")
    }

    @Test func appIDRoundTripsAsAString() throws {
        let id = TizenAppID("org.tizen.browser")!
        let data = try JSONEncoder().encode([id])
        #expect(String(decoding: data, as: UTF8.self) == "[\"org.tizen.browser\"]")
        #expect(try JSONDecoder().decode([TizenAppID].self, from: data) == [id])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([TizenAppID].self, from: Data("[\"a;b\"]".utf8)) }
    }
}
