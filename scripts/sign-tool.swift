import CryptoKit
import Foundation

// Release signing for Tether updates (Ed25519). The private key never leaves the maintainer's Mac and is never committed;
// the matching public key is built into the app (Updater.publicKey), so a hijacked GitHub account can't push a trusted update.
//   sign-tool keygen <private-key-file>              creates a key (mode 600) and prints the public key
//   sign-tool public <private-key-file>              prints the public key
//   sign-tool sign-update <key> <file> <version>     prints the version-bound signature the app requires
//   sign-tool verify <public-key> <file> <sig> <ver> checks that signature, exit 0 if valid
let a = CommandLine.arguments
func fail(_ m: String) -> Never { FileHandle.standardError.write(Data((m + "\n").utf8)); exit(1) }
guard a.count >= 3 else { fail("usage: sign-tool keygen|public|sign-update|verify …") }
let label = "tether-update"
func loadKey() -> Curve25519.Signing.PrivateKey {
    guard let t = try? String(contentsOf: URL(fileURLWithPath: a[2]), encoding: .utf8), let d = Data(base64Encoded: t.trimmingCharacters(in: .whitespacesAndNewlines)),
          let k = try? Curve25519.Signing.PrivateKey(rawRepresentation: d) else { fail("couldn't read the key at \(a[2])") }
    return k
}
switch a[1] {
case "keygen":
    guard !FileManager.default.fileExists(atPath: a[2]) else { fail("\(a[2]) already exists, not overwriting") }
    let dir = URL(fileURLWithPath: a[2]).deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let k = Curve25519.Signing.PrivateKey()
    guard FileManager.default.createFile(atPath: a[2], contents: Data(k.rawRepresentation.base64EncodedString().utf8), attributes: [.posixPermissions: 0o600]) else { fail("couldn't write the key") }
    print(k.publicKey.rawRepresentation.base64EncodedString())
case "public": print(loadKey().publicKey.rawRepresentation.base64EncodedString())
case "sign-update":
    guard a.count >= 5, let d = try? Data(contentsOf: URL(fileURLWithPath: a[3]), options: .mappedIfSafe),
          let s = try? loadKey().signature(for: Data("\(label)\nv\(a[4])\n".utf8) + d) else { fail("couldn't sign") }
    print(s.base64EncodedString())
case "verify":
    guard a.count >= 6, let pk = Data(base64Encoded: a[2]), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: pk),
          let d = try? Data(contentsOf: URL(fileURLWithPath: a[3]), options: .mappedIfSafe),
          let text = try? String(contentsOfFile: a[4], encoding: .utf8),
          let sig = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { fail("couldn't read the inputs") }
    guard key.isValidSignature(sig, for: Data("\(label)\nv\(a[5])\n".utf8) + d) else { fail("INVALID signature") }
    print("valid")
default: fail("unknown command")
}
