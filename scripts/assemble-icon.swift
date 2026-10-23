import Foundation

// ICNS stores each standard/Retina size as a typed PNG element.
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let sizes = [("icp4", "16x16"), ("ic11", "16x16@2x"), ("icp5", "32x32"), ("ic12", "32x32@2x"),
             ("ic07", "128x128"), ("ic13", "128x128@2x"), ("ic08", "256x256"), ("ic14", "256x256@2x"),
             ("ic09", "512x512"), ("ic10", "512x512@2x")]
func length(_ value: Int) -> Data {
    var bigEndian = UInt32(value).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}
var elements = Data()
for (type, name) in sizes {
    let png = try Data(contentsOf: input.appendingPathComponent("icon_\(name).png"))
    precondition(png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]), "Expected PNG representation")
    elements += Data(type.utf8) + length(png.count + 8) + png
}
try (Data("icns".utf8) + length(elements.count + 8) + elements).write(to: output, options: .atomic)
