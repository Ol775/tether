import Testing
@testable import TetherCore

struct ConnectionEndpointTests {
    @Test func parsesAddressAndPastedPort() throws {
        let target = try ConnectionEndpoint(address: " 192.168.1.10:37211\n", port: "5555")
        #expect(target.host == "192.168.1.10")
        #expect(target.port == 37211)
        let hostname = try ConnectionEndpoint(address: "android.local", port: " 26101 ")
        #expect(hostname.host == "android.local")
        #expect(hostname.port == 26101)
    }

    @Test(arguments: ["", "0", "65536", "-1", "+5555", "5.5", "five", "１２３", "99999999999999999999999999"])
    func rejectsInvalidPorts(_ port: String) {
        #expect(throws: DeviceError.invalidHost) { try ConnectionEndpoint(address: "192.168.1.10", port: port) }
    }

    @Test(arguments: ["", "-host", "host name", "https://host", "host:", "host:0", "host:5:5", "host;reboot"])
    func rejectsInvalidAddresses(_ address: String) {
        #expect(throws: DeviceError.invalidHost) { try ConnectionEndpoint(address: address, port: "5555") }
    }
}
