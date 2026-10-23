import Foundation
import Testing
@testable import TetherCore

struct TizenCatalogTests {
    let tv2021 = TizenDevice(serial: "s:1", model: "QE55Q80AAT", modelYear: 2021, tizenVersion: "6.0", shellEnabled: false, rootAvailable: false)

    func json(_ entries: String) -> Data { Data(#"{"version":1,"entries":[\#(entries)]}"#.utf8) }
    func entry(app: String = "org.example.a", tier: String = "safe", breaks: String? = nil, year: String = "null", title: String = "T") -> String {
        let b = breaks.map { #""breaks":"\#($0)","# } ?? ""
        return #"{"app":"\#(app)","tier":"\#(tier)","title":"\#(title)","description":"d",\#(b)"removableFromYear":\#(year),"source":"s"}"#
    }

    @Test func decodesBundledCatalog() throws {
        let url = try #require(Resources.url("tizen-catalog", "json"))
        let catalog = try TizenCatalog.decode(Data(contentsOf: url))
        #expect(!catalog.entries.isEmpty)
        #expect(catalog.entries.allSatisfy { $0.source.contains("not verified") })
    }

    @Test func rejectsDuplicatesMissingBreaksAndEmptyFields() {
        #expect(throws: CatalogError.duplicate("org.example.a")) { try TizenCatalog.decode(json(entry() + "," + entry())) }
        #expect(throws: CatalogError.missingBreaks("org.example.a")) { try TizenCatalog.decode(json(entry(tier: "expert"))) }
        #expect(throws: CatalogError.emptyField("org.example.a", "title")) { try TizenCatalog.decode(json(entry(title: " "))) }
        #expect(throws: CatalogError.unsupportedVersion(2)) { try TizenCatalog.decode(Data(#"{"version":2,"entries":[]}"#.utf8)) }
    }

    @Test func rejectsHostileAppIDs() {
        #expect(throws: (any Error).self) { try TizenCatalog.decode(json(entry(app: "a;rm"))) }
    }

    @Test func hintMarksPreloadsAsLikelyLocked() throws {
        let catalog = try TizenCatalog.decode(json([entry(app: "org.example.a"), entry(app: "org.example.b", year: "2019"), entry(app: "org.example.c", year: "2022")].joined(separator: ",")))
        let hints = Dictionary(uniqueKeysWithValues: catalog.entries.map { ($0.app.value, catalog.likelyLocked($0, on: tv2021)) })
        #expect(hints == ["org.example.a": true, "org.example.b": false, "org.example.c": true])
    }

    @Test func filtersToInstalled() throws {
        let catalog = try TizenCatalog.decode(json(entry(app: "org.example.a") + "," + entry(app: "org.example.b")))
        #expect(catalog.entries(installed: [TizenAppID("org.example.b")!]).map(\.app.value) == ["org.example.b"])
    }
}
