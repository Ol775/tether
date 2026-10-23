import Foundation
import Testing
@testable import TetherCore

struct ConsoleGuardTests {
    static let allowed = [
        "ls /sdcard", "getprop ro.product.model", "settings get global adb_enabled", "settings list secure",
        "pm list packages -u", "pm path com.amazon.recess", "dumpsys battery", "ls 2>/dev/null", "ls /sdcard 2>&1",
        "cat /proc/cpuinfo | grep Hardware", "ps -A | grep adb", "wm size", "date",
    ]
    static let confirmed = [
        "rm -rf /sdcard/x", "ls; rm x", "echo $(reboot)", "echo `pm clear a.b`", "ls && settings put global x 1",
        "ls || reboot", "ls | tee /sdcard/o", "ls > /sdcard/o", "dumpsys battery set level 5", "find / -delete",
        "r\\m x", "'rm' x", "\"rm\" x", "sh -c \"rm x\"", "eval reboot", "su -c reboot", "echo hi\nrm x", "{ rm x; }",
        "pm uninstall com.a.b", "pm disable-user com.a.b", "pm clear com.a.b", "settings put global a b", "wm size 100x100",
        "cmd package install-existing x.y", "svc wifi disable", "date -s 2020", "mount -o remount /system", "unknowncmd --flag",
        "FOO=1 reboot", "ls $(echo rm) x",
    ]

    @Test(arguments: allowed) func allows(_ command: String) {
        #expect(ConsoleGuard.classify(command) == .allow, "\(command)")
    }

    @Test(arguments: confirmed) func confirms(_ command: String) {
        guard case .confirm(let reason) = ConsoleGuard.classify(command) else {
            Issue.record("\(command) was allowed"); return
        }
        #expect(!reason.isEmpty)
    }

    let device = DeviceProfile(serial: "192.168.1.5:5555", vendor: "x", model: "m", androidVersion: "9", sdk: 28, abis: [], platform: .android)

    @Test func runRefusesUnconfirmedDestructiveCommands() async throws {
        let fake = try FakeADB()
        let log = ChangeLog(file: fake.dir.appendingPathComponent("log"))
        await #expect(throws: ConsoleError.needsConfirmation("deletes files")) {
            try await Console.run("rm -rf /sdcard/x", on: device, adb: fake.runner, log: log)
        }
        #expect(fake.calls().isEmpty)
        _ = try await Console.run("rm -rf /sdcard/x", on: device, adb: fake.runner, log: log, confirmed: true)
        #expect(fake.calls().count == 1)
    }

    @Test func runExecutesAllowedCommandsAndLogsThem() async throws {
        let fake = try FakeADB(files: ["props.txt": "ro.product.model=AFTMM\n"])
        let log = fake.dir.appendingPathComponent("log")
        let out = try await Console.run("getprop ro.product.model", on: device, adb: fake.runner, log: ChangeLog(file: log))
        #expect(out.trimmingCharacters(in: .whitespacesAndNewlines) == "AFTMM")
        #expect(fake.calls() == ["-P 5038 -s 192.168.1.5:5555 shell getprop ro.product.model"])
        #expect(try String(contentsOf: log, encoding: .utf8).contains("getprop ro.product.model"))
    }
}
