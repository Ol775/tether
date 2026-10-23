import Foundation

func fixture(_ name: String) -> String {
    let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    return try! String(contentsOf: url, encoding: .utf8)
}
