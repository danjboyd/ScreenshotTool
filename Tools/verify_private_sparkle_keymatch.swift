import Foundation
import CryptoKit

private let expectedPublicKey = "fXqmzuRxV6TkC42/QrZAZSyYsvieYCnbDf7qO3/afs8="
private let expectedPayload = "ScreenshotTool Sparkle key-match proof v1\n" +
    "source=01c1ad58677b46774e7bc56ea5f908aaffb637df\n"

private func require(_ condition: Bool, _ reason: String) {
    guard condition else {
        fputs("private Sparkle key-match failed: \(reason)\n", stderr)
        exit(1)
    }
}

require(CommandLine.arguments.count == 4, "expected dummy, attributes and Info.plist paths")
let payload = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
require(payload == Data(expectedPayload.utf8), "unexpected dummy payload")
let attributes = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
let infoData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
let keyText = info?["SUPublicEDKey"] as? String
require(keyText == expectedPublicKey, "unexpected bundled public key")

func attribute(_ name: String) -> String? {
    let pattern = "(?:^|\\s)" + NSRegularExpression.escapedPattern(for: name) + "=\"([^\"]+)\""
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)),
          let range = Range(match.range(at: 1), in: attributes) else { return nil }
    return String(attributes[range])
}

require(attribute("sparkle:length") == String(payload.count),
        "sparkle:length missing or differs from \(payload.count) payload bytes")
guard let encodedSignature = attribute("sparkle:edSignature"),
      let signature = Data(base64Encoded: encodedSignature), signature.count == 64,
      let keyText, let key = Data(base64Encoded: keyText), key.count == 32 else {
    fputs("private Sparkle key-match failed: missing public signature data\n", stderr)
    exit(1)
}
let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key)
require(publicKey.isValidSignature(signature, for: payload), "Ed25519 signature does not verify")
let hash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
print("Sparkle key match: PASS")
print("dummy_sha256=\(hash)")
