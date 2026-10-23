import Foundation

/// Pure parsers for adb output. Garbage lines are skipped, never thrown on.
public enum Parsers {
    public static func devices(_ output: String) -> [(serial: String, state: String, model: String?)] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("*") || line.hasPrefix("List of devices") { return nil }
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 2 else { return nil }
            let model = tokens.dropFirst(2).first { $0.hasPrefix("model:") }.map { String($0.dropFirst(6)) }
            return (tokens[0], tokens[1], model)
        }
    }

    public static func profile(serial: String, getprop: String) -> DeviceProfile {
        var props: [String: String] = [:]
        for line in getprop.split(whereSeparator: \.isNewline) {
            // [key]: [value]
            guard let split = line.range(of: "]: [") , line.hasPrefix("["), line.hasSuffix("]") else { continue }
            props[String(line[line.index(after: line.startIndex)..<split.lowerBound])] = String(line[split.upperBound..<line.index(before: line.endIndex)])
        }
        let vendor = (props["ro.product.manufacturer"] ?? "unknown").lowercased()
        let abiList = props["ro.product.cpu.abilist"] ?? props["ro.product.cpu.abi"] ?? ""
        return DeviceProfile(
            serial: serial,
            vendor: vendor,
            model: props["ro.product.model"] ?? "Unknown",
            androidVersion: props["ro.build.version.release"] ?? "?",
            sdk: Int(props["ro.build.version.sdk"] ?? "") ?? 0,
            abis: abiList.split(separator: ",").map(String.init),
            platform: vendor == "amazon" ? .fireOS : .android)
    }

    public static func packages(all: String, installed: String, disabled: String) -> [PackageSnapshot] {
        let all = names(all), installed = names(installed), disabled = names(disabled)
        return all.union(installed).sorted().map { name in
            .init(name: name, state: !installed.contains(name) ? .removedForUser : disabled.contains(name) ? .disabled : .enabled)
        }
    }

    public static func settings(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            result[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        return result
    }

    /// `wm density` prints an "Override density" line only when the user has changed it.
    public static func densityOverride(_ output: String) -> Int? {
        output.split(whereSeparator: \.isNewline)
            .first { $0.hasPrefix("Override density:") }
            .flatMap { Int($0.dropFirst("Override density:".count).trimmingCharacters(in: .whitespaces)) }
    }

    private static func names(_ output: String) -> Set<PackageName> {
        Set(output.split(whereSeparator: \.isNewline).compactMap { line in
            line.hasPrefix("package:") ? PackageName(String(line.dropFirst(8))) : nil
        })
    }
}
