import Foundation

/// Parsers for `sdb` output. Formats for `capability` and `applist` are assumed from community reports
/// (see the fixtures) and are tolerant: lines that don't fit are dropped, never guessed at.
public enum TizenParsers {
    public static func devices(_ text: String) -> [(serial: String, state: String)] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
            guard parts.count >= 2, !line.hasPrefix("List of devices"), parts[0].contains(":") else { return nil }
            return (String(parts[0]), String(parts[1]))
        }
    }

    public static func capability(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            result[String(line[..<colon]).trimmingCharacters(in: .whitespaces)] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    public static func device(serial: String, capability cap: [String: String]) -> TizenDevice {
        let model = cap["model_name"] ?? "Samsung TV"
        return TizenDevice(
            serial: serial,
            deviceID: cap["duid"].flatMap { isRealID($0) ? $0 : nil },
            model: model,
            modelYear: modelYear(fromModelCode: model),
            tizenVersion: cap["platform_version"] ?? "?",
            shellEnabled: cap["intershell_support"] == "enabled",
            rootAvailable: cap["sdbd_rootperm"] == "enabled")
    }

    /// `'Name'   'app.id'` pairs; anything with an id that fails validation is dropped.
    public static func apps(_ text: String) -> [TizenApp] {
        let pair = #/'([^']*)'\s+'([^']*)'/#
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let m = line.firstMatch(of: pair), let id = TizenAppID(String(m.2)) else { return nil }
            return TizenApp(id: id, name: String(m.1))
        }
    }

    /// Samsung model codes carry a year letter: `QE55Q80AAT` → A (2021), `UE50RU7100` → R (2019).
    public static func modelYear(fromModelCode code: String) -> Int? {
        guard let m = code.firstMatch(of: #/^[A-Z]{2}\d{2}([A-Z]{1,2})(\d+)?(.*)$/#) else { return nil }
        let letter = m.3.first ?? m.1.first
        return letter.flatMap { yearByLetter[$0] }
    }

    private static let yearByLetter: [Character: Int] = ["M": 2017, "N": 2018, "R": 2019, "T": 2020, "A": 2021, "B": 2022, "C": 2023, "D": 2024, "F": 2025]

    private static func isRealID(_ s: String) -> Bool {
        let t = s.lowercased()
        return t.count >= 4 && !["unknown", "null", "none"].contains(t) && !t.allSatisfy { $0 == "0" }
    }
}
