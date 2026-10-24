import CryptoKit
import Foundation
import Security
import Testing
import CTizenXML
@testable import TetherCore

/// Verifies the native signer produces a well-formed, cryptographically valid W3C widget signature pair.
/// Uses a throwaway RSA key generated per run (never the real Samsung cert), so it proves structure and
/// the sign/verify maths; conformance to a real `tizen`-signed package was proven out of band.
/// Serialised: SecPKCS12Import touches the keychain and is unreliable under Swift Testing's parallel
/// execution (intermittent errSec failures). Production signs once, serially, so this only affects tests.
@Suite(.serialized)
struct WidgetSignerTests {

    /// A sample widget: top-level files plus a nested one, to exercise recursion and relative URIs.
    func sampleWidget() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wgtpkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("js"), withIntermediateDirectories: true)
        try "<widget><tizen:application id=\"a.b\"/></widget>".write(to: dir.appendingPathComponent("config.xml"), atomically: true, encoding: .utf8)
        try "<html></html>".write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try "console.log(1)".write(to: dir.appendingPathComponent("js/app.js"), atomically: true, encoding: .utf8)
        return dir
    }

    /// Generates a self-signed RSA key/cert and returns its PKCS#12 bytes + password.
    func testIdentity() throws -> WidgetSigner.Identity {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("id-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        func openssl(_ args: [String]) throws {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl"); p.arguments = args
            try p.run(); p.waitUntilExit()
            guard p.terminationStatus == 0 else { throw TizenError.nothingToDo }
        }
        let key = d.appendingPathComponent("k.pem"), crt = d.appendingPathComponent("c.pem"), p12 = d.appendingPathComponent("id.p12")
        try openssl(["genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048", "-out", key.path])
        try openssl(["req", "-x509", "-new", "-key", key.path, "-days", "3", "-subj", "/CN=TetherTest", "-out", crt.path])
        // /usr/bin/openssl is LibreSSL; its default p12 is already the legacy format the Security framework imports.
        try openssl(["pkcs12", "-export", "-inkey", key.path, "-in", crt.path, "-out", p12.path, "-passout", "pass:test"])
        return WidgetSigner.Identity(p12: try Data(contentsOf: p12), password: "test")
    }

    func canonicalSignedInfo(_ signatureXML: Data) -> Data {
        let wrapper = String(data: signatureXML, encoding: .utf8)!   // the file is itself the Signature element
        var outLen: Int32 = 0
        let r = wrapper.withCString { x in tether_c14n_subtree(x, Int32(strlen(x)), "(//*[local-name()='SignedInfo'])[1]", TETHER_C14N_EXCLUSIVE, &outLen) }!
        defer { tether_xml_free(r) }
        return Data(bytes: r, count: Int(outLen))
    }

    func publicKey(fromSignature xml: String) throws -> SecKey {
        // First <X509Certificate> → DER → SecCertificate → public key.
        let b64 = xml.components(separatedBy: "<X509Certificate>")[1].components(separatedBy: "</X509Certificate>")[0]
        let der = Data(base64Encoded: b64.filter { !$0.isWhitespace })!
        let cert = SecCertificateCreateWithData(nil, der as CFData)!
        return SecCertificateCopyKey(cert)!
    }

    func verify(_ sigFile: URL) throws -> Bool {
        let data = try Data(contentsOf: sigFile)
        let xml = String(data: data, encoding: .utf8)!
        let signedInfo = canonicalSignedInfo(data)
        let sigB64 = xml.components(separatedBy: "<SignatureValue>")[1].components(separatedBy: "</SignatureValue>")[0]
        let sig = Data(base64Encoded: sigB64.filter { !$0.isWhitespace })!
        let key = try publicKey(fromSignature: xml)
        return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA512, signedInfo as CFData, sig as CFData, nil)
    }

    @Test func producesTwoValidSignatures() throws {
        let dir = try sampleWidget()
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("signed-\(UUID().uuidString).wgt")
        try WidgetSigner.sign(packageDir: dir, author: try testIdentity(), distributor: try testIdentity(), output: out)

        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("author-signature.xml").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("signature1.xml").path))
        #expect(FileManager.default.fileExists(atPath: out.path))

        // Both signatures verify against their embedded certificate over the canonical SignedInfo.
        #expect(try verify(dir.appendingPathComponent("author-signature.xml")))
        #expect(try verify(dir.appendingPathComponent("signature1.xml")))
    }

    @Test func referencesEveryContentFileWithItsRealDigest() throws {
        let dir = try sampleWidget()
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("signed-\(UUID().uuidString).wgt")
        try WidgetSigner.sign(packageDir: dir, author: try testIdentity(), distributor: try testIdentity(), output: out)
        // base64 is wrapped at 76 in the output, so compare with whitespace removed.
        func stripped(_ u: String) throws -> String {
            try String(contentsOf: dir.appendingPathComponent(u), encoding: .utf8).filter { !$0.isWhitespace }
        }
        let author = try stripped("author-signature.xml")
        for (uri, file) in [("config.xml", "config.xml"), ("index.html", "index.html"), ("js/app.js", "js/app.js")] {
            let d = Data(SHA512.hash(data: try Data(contentsOf: dir.appendingPathComponent(file))))
            #expect(author.contains("URI=\"\(uri)\""))
            #expect(author.contains("<DigestValue>\(d.base64EncodedString())</DigestValue>"))
        }
        // The distributor signature must reference the author signature's raw bytes.
        let dist = try stripped("signature1.xml")
        let authorDigest = Data(SHA512.hash(data: try Data(contentsOf: dir.appendingPathComponent("author-signature.xml")))).base64EncodedString()
        #expect(dist.contains("URI=\"author-signature.xml\""))
        #expect(dist.contains("<DigestValue>\(authorDigest)</DigestValue>"))
    }

    @Test func wrongPasswordFailsClearly() throws {
        let dir = try sampleWidget()
        var id = try testIdentity()
        id = WidgetSigner.Identity(p12: id.p12, password: "wrong")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("x.wgt")
        #expect(throws: (any Error).self) {
            try WidgetSigner.sign(packageDir: dir, author: id, distributor: id, output: out)
        }
    }
}
