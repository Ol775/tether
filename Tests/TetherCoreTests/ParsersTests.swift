import Testing
@testable import TetherCore

struct ParsersTests {
    @Test func devicesParsesIPSerialAndModel() {
        let devices = Parsers.devices(fixture("devices-l.txt"))
        #expect(devices.count == 2)
        #expect(devices[0].serial == "192.168.1.5:5555")
        #expect(devices[0].state == "device")
        #expect(devices[0].model == "AFTMM")
        #expect(devices[1].state == "unauthorized")
        #expect(devices[1].model == nil)
    }

    @Test func profileDetectsFireOS() {
        let p = Parsers.profile(serial: "s", getprop: fixture("getprop-firetv.txt"))
        #expect(p.platform == .fireOS)
        #expect(p.vendor == "amazon")
        #expect(p.model == "AFTMM")
        #expect(p.sdk == 28)
        #expect(p.abis == ["armeabi-v7a", "armeabi"])
    }

    @Test func profileDetectsPixelAsAndroid() {
        let p = Parsers.profile(serial: "s", getprop: fixture("getprop-pixel.txt"))
        #expect(p.platform == .android)
        #expect(p.vendor == "google")
        #expect(p.androidVersion == "15")
    }

    @Test func packagesDerivesRemovedForUser() {
        let pkgs = Parsers.packages(
            all: fixture("packages-all.txt"),
            installed: fixture("packages-installed.txt"),
            disabled: fixture("packages-disabled.txt"))
        let byName = Dictionary(uniqueKeysWithValues: pkgs.map { ($0.name.value, $0.state) })
        #expect(byName["com.amazon.removed"] == .removedForUser)
        #expect(byName["com.amazon.off"] == .disabled)
        #expect(byName["com.amazon.recess"] == .enabled)
    }

    @Test func packagesDropsHostileLines() {
        let pkgs = Parsers.packages(all: "package:com.ok.app\npackage:com.a;rm -rf /\n", installed: "package:com.ok.app\n", disabled: "")
        #expect(pkgs.map(\.name.value) == ["com.ok.app"])
    }

    @Test func settingsHandlesEqualsInValue() {
        let s = Parsers.settings(fixture("settings-global.txt"))
        #expect(s["private_dns_specifier"] == "dns.example=1")
        #expect(s["empty_value"] == "")
        #expect(s["adb_enabled"] == "1")
    }

    @Test func packageNameRejectsHostile() {
        for bad in ["com.a;rm -rf /", "$(id)", "", "com..x", "x", "com.a b", "com.a\ncom.b"] {
            #expect(PackageName(bad) == nil, "\(bad)")
        }
    }

    @Test func packageNameAcceptsReal() {
        #expect(PackageName("com.amazon.recess")?.value == "com.amazon.recess")
    }

    @Test func profileKeepsAStableIDApartFromTheAddress() {
        let withSerial = Parsers.profile(serial: "10.0.0.2:5555", getprop: "[ro.serialno]: [G070VM123]\n")
        #expect(withSerial.deviceID == "G070VM123" && withSerial.serial == "10.0.0.2:5555")
        let without = Parsers.profile(serial: "10.0.0.2:5555", getprop: "")
        #expect(without.deviceID == "10.0.0.2:5555")
    }
}
