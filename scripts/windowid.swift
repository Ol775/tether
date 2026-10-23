// Prints the CGWindowID of the largest on-screen window owned by the named process.
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "Tether"
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
let best = windows
    .filter { ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int) == 0 }
    .max { area($0) < area($1) }
func area(_ w: [String: Any]) -> Double {
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return (b["Width"] ?? 0) * (b["Height"] ?? 0)
}
if let id = best?[kCGWindowNumber as String] as? Int { print(id) } else { exit(1) }
