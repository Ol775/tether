import CryptoKit
import Foundation
import Security
import CTizenXML

/// Signs a Tizen `.wgt` widget with W3C Widget Digital Signatures, reproducing exactly what Samsung's
/// `tizen package -t wgt -s <profile>` produces — so the install path no longer needs the Tizen CLI.
///
/// Verified against a real `tizen`-signed package: the file digests, both `#prop` canonical digests, and
/// the distributor's signature over `author-signature.xml` all match, and the real author SignatureValue
/// verifies against this code's canonical `SignedInfo`. Canonicalisation is done by libxml2 (via
/// `CTizenXML`); RSA-SHA512 signing by the Security framework.
public enum WidgetSigner {
    public struct Identity: Sendable {
        /// Raw PKCS#12 bytes (author.p12 / distributor.p12).
        public let p12: Data
        /// The passphrase that unlocks the p12. Supplied by the user; never stored.
        public let password: String
        public init(p12: Data, password: String) {
            self.p12 = p12
            self.password = password
        }
    }

    private static let dsigNS = "http://www.w3.org/2000/09/xmldsig#"

    /// Writes `author-signature.xml` then `signature1.xml` into `packageDir`, then zips the directory to
    /// `output` (a `.wgt`). The content files must already be in place; any existing signature files are
    /// replaced. Throws `JellyfinError.buildFailed` with a specific reason on any failure.
    public static func sign(packageDir: URL, author: Identity, distributor: Identity, output: URL) throws {
        // Content files = every regular file under the root except the signature files themselves.
        let signatureNames: Set<String> = ["author-signature.xml", "signature1.xml"]
        let contentFiles = try Self.contentFiles(in: packageDir)
            .filter { !signatureNames.contains($0.relativePath) }
            .sorted { $0.relativePath < $1.relativePath }
        guard !contentFiles.isEmpty else { throw JellyfinError.buildFailed("The widget package has no files to sign.") }

        // Digest every content file once (raw bytes, sha512); both signatures reference the same hashes.
        let contentRefs: [(uri: String, digest: String)] = try contentFiles.map {
            ($0.uri, Self.sha512Base64(try Data(contentsOf: $0.url, options: .mappedIfSafe)))
        }

        // Author signature: content files + #prop, role-author.
        let authorXML = try buildSignature(id: "AuthorSignature", role: "author", identity: author, references: contentRefs)
        try Data(authorXML.utf8).write(to: packageDir.appendingPathComponent("author-signature.xml"))

        // Distributor signature: author-signature.xml (raw bytes) + content files + #prop, role-distributor.
        let distRefs = [("author-signature.xml", Self.sha512Base64(Data(authorXML.utf8)))] + contentRefs
        let distributorXML = try buildSignature(id: "DistributorSignature", role: "distributor", identity: distributor, references: distRefs)
        try Data(distributorXML.utf8).write(to: packageDir.appendingPathComponent("signature1.xml"))

        try zip(directory: packageDir, to: output)
    }

    // MARK: Signature assembly

    private static func buildSignature(id: String, role: String, identity: Identity,
                                       references: [(uri: String, digest: String)]) throws -> String {
        let (key, certsDER) = try loadIdentity(identity)

        // The SignatureProperties object, whose canonical (c14n 1.1) digest is referenced as #prop.
        let objectInner =
            "<SignatureProperties xmlns:dsp=\"http://www.w3.org/2009/xmldsig-properties\">"
            + "<SignatureProperty Id=\"profile\" Target=\"#\(id)\"><dsp:Profile URI=\"http://www.w3.org/ns/widgets-digsig#profile\"></dsp:Profile></SignatureProperty>"
            + "<SignatureProperty Id=\"role\" Target=\"#\(id)\"><dsp:Role URI=\"http://www.w3.org/ns/widgets-digsig#role-\(role)\"></dsp:Role></SignatureProperty>"
            + "<SignatureProperty Id=\"identifier\" Target=\"#\(id)\"><dsp:Identifier></dsp:Identifier></SignatureProperty>"
            + "</SignatureProperties>"
        let objectXML = "<Object Id=\"prop\">\(objectInner)</Object>"

        // Digest the #prop object as it would appear inside the Signature (default dsig namespace in scope).
        let propWrapper = "<Signature xmlns=\"\(dsigNS)\">\(objectXML)</Signature>"
        let propC14N = try canonicalize(propWrapper, xpath: "(//*[@Id='prop'])[1]", mode: TETHER_C14N_1_1)
        let propDigest = Self.sha512Base64(propC14N)

        // SignedInfo: a Reference per file (raw bytes, sha512) plus the #prop reference (c14n11 transform).
        var refsXML = ""
        for ref in references {
            refsXML +=
                "<Reference URI=\"\(ref.uri)\">"
                + "<DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha512\"></DigestMethod>"
                + "<DigestValue>\(ref.digest)</DigestValue></Reference>"
        }
        refsXML +=
            "<Reference URI=\"#prop\"><Transforms>"
            + "<Transform Algorithm=\"http://www.w3.org/2006/12/xml-c14n11\"></Transform></Transforms>"
            + "<DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha512\"></DigestMethod>"
            + "<DigestValue>\(propDigest)</DigestValue></Reference>"
        let signedInfo =
            "<SignedInfo>"
            + "<CanonicalizationMethod Algorithm=\"http://www.w3.org/2001/10/xml-exc-c14n#\"></CanonicalizationMethod>"
            + "<SignatureMethod Algorithm=\"http://www.w3.org/2001/04/xmldsig-more#rsa-sha512\"></SignatureMethod>"
            + refsXML + "</SignedInfo>"

        // Sign the exclusively-canonicalised SignedInfo (as it sits inside the Signature element).
        let siWrapper = "<Signature xmlns=\"\(dsigNS)\">\(signedInfo)</Signature>"
        let siC14N = try canonicalize(siWrapper, xpath: "(//*[local-name()='SignedInfo'])[1]", mode: TETHER_C14N_EXCLUSIVE)
        let signatureValue = try rsaSHA512(siC14N, key: key)

        let certsXML = certsDER.map { "<X509Certificate>\(Self.base64($0))</X509Certificate>" }.joined()
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>\n"
            + "<Signature xmlns=\"\(dsigNS)\" Id=\"\(id)\">"
            + signedInfo
            + "<SignatureValue>\(Self.base64(signatureValue))</SignatureValue>"
            + "<KeyInfo><X509Data>\(certsXML)</X509Data></KeyInfo>"
            + objectXML
            + "</Signature>"
    }

    // MARK: Crypto

    private static func loadIdentity(_ identity: Identity) throws -> (SecKey, [Data]) {
        var items: CFArray?
        let status = SecPKCS12Import(identity.p12 as CFData,
                                     [kSecImportExportPassphrase as String: identity.password] as CFDictionary,
                                     &items)
        guard status == errSecSuccess, let dicts = items as? [[String: Any]], let first = dicts.first else {
            throw JellyfinError.buildFailed("Couldn't open the signing certificate — check the password. (\(status))")
        }
        // SecKit stores the identity under kSecImportItemIdentity; the chain under kSecImportItemCertChain.
        let identityRef = first[kSecImportItemIdentity as String] as! SecIdentity
        var key: SecKey?
        guard SecIdentityCopyPrivateKey(identityRef, &key) == errSecSuccess, let privateKey = key else {
            throw JellyfinError.buildFailed("The signing certificate has no usable private key.")
        }
        let chain = first[kSecImportItemCertChain as String] as? [SecCertificate] ?? []
        let certsDER = chain.map { SecCertificateCopyData($0) as Data }
        guard !certsDER.isEmpty else { throw JellyfinError.buildFailed("The signing certificate chain is empty.") }
        return (privateKey, certsDER)
    }

    private static func rsaSHA512(_ data: Data, key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA512, data as CFData, &error) else {
            let msg = (error?.takeRetainedValue()).map { CFErrorCopyDescription($0) as String } ?? "unknown error"
            throw JellyfinError.buildFailed("Signing failed: \(msg)")
        }
        return sig as Data
    }

    // MARK: Digests / canonicalisation

    private static func sha512Base64(_ data: Data) -> String { base64(Data(SHA512.hash(data: data))) }
    private static func base64(_ data: Data) -> String { data.base64EncodedString() }

    private static func canonicalize(_ xml: String, xpath: String, mode: Int32) throws -> Data {
        var outLen: Int32 = 0
        let result: UnsafeMutablePointer<CChar>? = xml.withCString { xmlPtr in
            xpath.withCString { xpPtr in
                tether_c14n_subtree(xmlPtr, Int32(strlen(xmlPtr)), xpPtr, mode, &outLen)
            }
        }
        guard let result else { throw JellyfinError.buildFailed("Canonicalisation failed for \(xpath).") }
        defer { tether_xml_free(result) }
        return Data(bytes: result, count: Int(outLen))
    }

    // MARK: Package walking / zipping

    private struct ContentFile { let url: URL; let relativePath: String; let uri: String }

    private static func contentFiles(in root: URL) throws -> [ContentFile] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var out: [ContentFile] = []
        let rootPath = root.standardizedFileURL.path
        for case let url as URL in e {
            guard (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(rootPath + "/") else { continue }
            let rel = String(full.dropFirst(rootPath.count + 1))
            out.append(ContentFile(url: url, relativePath: rel, uri: uriEncode(rel)))
        }
        return out
    }

    /// The Reference URI is the file path relative to the widget root. Encode only characters that would
    /// break the attribute or the IRI; keep path separators and the common filename characters literal.
    private static func uriEncode(_ relativePath: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "/-._~")
        return relativePath.addingPercentEncoding(withAllowedCharacters: allowed) ?? relativePath
    }

    private static func zip(directory: URL, to output: URL) throws {
        try? FileManager.default.removeItem(at: output)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        // -r recurse, -X no extra attributes; run from inside the dir so paths are root-relative.
        p.arguments = ["-r", "-X", "-q", output.path, "."]
        p.currentDirectoryURL = directory
        let err = Pipe(); p.standardError = err
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw JellyfinError.buildFailed("Packaging the signed widget failed: \(msg)")
        }
    }
}
