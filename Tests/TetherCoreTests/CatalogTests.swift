import Foundation
import Testing
@testable import TetherCore

struct CatalogTests {
    func entry(_ pkg: String, vendors: [String] = ["amazon"], tier: String = "safe", breaks: String? = nil,
               description: String = "Does a thing.", source: String = "test") -> [String: Any] {
        var e: [String: Any] = ["package": pkg, "vendors": vendors, "tier": tier, "title": pkg, "description": description, "source": source]
        if let breaks { e["breaks"] = breaks }
        return e
    }

    func json(_ entries: [[String: Any]], version: Int = 1) -> Data {
        try! JSONSerialization.data(withJSONObject: ["version": version, "entries": entries])
    }

    let fireTV = DeviceProfile(serial: "s", vendor: "amazon", model: "AFTMM", androidVersion: "9", sdk: 28, abis: [], platform: .fireOS)

    @Test func rejectsDuplicates() {
        #expect(throws: CatalogError.duplicate("com.a.b")) {
            try Catalog.decode(json([entry("com.a.b"), entry("com.a.b")]))
        }
    }

    @Test func samePackageDifferentVendorIsFine() throws {
        _ = try Catalog.decode(json([entry("com.a.b", vendors: ["amazon"]), entry("com.a.b", vendors: ["samsung"])]))
    }

    @Test func rejectsAdvancedAndExpertWithoutBreaks() {
        for tier in ["advanced", "expert"] {
            #expect(throws: CatalogError.missingBreaks("com.a.b")) {
                try Catalog.decode(json([entry("com.a.b", tier: tier)]))
            }
        }
    }

    @Test func rejectsEmptyDescriptionAndSource() {
        #expect(throws: CatalogError.emptyField("com.a.b", "description")) {
            try Catalog.decode(json([entry("com.a.b", description: " ")]))
        }
        #expect(throws: CatalogError.emptyField("com.a.b", "source")) {
            try Catalog.decode(json([entry("com.a.b", source: "")]))
        }
    }

    @Test func rejectsHostilePackageAndUnknownVersion() {
        #expect(throws: (any Error).self) { try Catalog.decode(json([entry("com.a;rm -rf /")])) }
        #expect(throws: CatalogError.unsupportedVersion(2)) { try Catalog.decode(json([], version: 2)) }
    }

    @Test func filtersByVendorAndInstalled() throws {
        let catalog = try Catalog.decode(json([
            entry("com.amazon.here"), entry("com.amazon.absent"), entry("com.samsung.other", vendors: ["samsung"]), entry("com.any.where", vendors: ["*"]),
        ]))
        let installed: Set<PackageName> = [PackageName("com.amazon.here")!, PackageName("com.samsung.other")!, PackageName("com.any.where")!]
        let names = catalog.entries(for: fireTV, installed: installed).map(\.package.value)
        #expect(names == ["com.amazon.here", "com.any.where"])
    }

    @Test func bundledCatalogIsValid() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cat-\(UUID())")
        let catalog = try CatalogStore(overrideDir: dir).load()
        #expect(!catalog.entries.isEmpty)
    }

    @Test func refreshWritesValidCatalogAndOverridesBundled() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cat-\(UUID())")
        let url = URL(string: "https://example.test/\(UUID())/catalog.json")!
        StubURLProtocol.stub(url, .init(status: 200, body: json([entry("com.only.one")])))
        let store = CatalogStore(overrideDir: dir)
        #expect(try await store.refresh(from: url, session: StubURLProtocol.session))
        #expect(try store.load().entries.map(\.package.value) == ["com.only.one"])
    }

    @Test func refreshKeepsOldOnInvalid() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cat-\(UUID())")
        let store = CatalogStore(overrideDir: dir)
        let good = URL(string: "https://example.test/\(UUID())/good.json")!
        StubURLProtocol.stub(good, .init(status: 200, body: json([entry("com.keep.me")])))
        _ = try await store.refresh(from: good, session: StubURLProtocol.session)
        let bad = URL(string: "https://example.test/\(UUID())/bad.json")!
        StubURLProtocol.stub(bad, .init(status: 200, body: json([entry("com.a.b", tier: "expert")])))
        await #expect(throws: CatalogError.self) { try await store.refresh(from: bad, session: StubURLProtocol.session) }
        #expect(try store.load().entries.map(\.package.value) == ["com.keep.me"])
    }

    @Test func refresh404ReturnsFalseAndNonHTTPSThrows() async throws {
        let store = CatalogStore(overrideDir: FileManager.default.temporaryDirectory.appendingPathComponent("cat-\(UUID())"))
        let missing = URL(string: "https://example.test/\(UUID())/nope.json")!
        #expect(try await store.refresh(from: missing, session: StubURLProtocol.session) == false)
        await #expect(throws: CatalogError.insecureURL) {
            try await store.refresh(from: URL(string: "http://example.test/c.json")!, session: StubURLProtocol.session)
        }
    }
}
