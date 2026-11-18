// Review draft for Tools/verify_macos_real_dmg_appcast.swift.
// Usage: swift verify_macos_real_dmg_appcast.swift <dmg> <appcast.xml> <version> <build> <dmg-sha256>
// Offline, public-key-only verification. Mounts the DMG read-only to inspect its packaged app;
// it never opens or runs the app. It detaches only the mount it created.
import Foundation
import CryptoKit

private let pinnedPublicKey = "fXqmzuRxV6TkC42/QrZAZSyYsvieYCnbDf7qO3/afs8="
private let expectedURL = "https://github.com/danjboyd/ScreenshotTool/releases/download/v0.4.0/ScreenshotTool-0.4.0-macOS.dmg"
private var ownedRootToClean: URL?
private var ownedMountToDetach: URL?

private func cleanupOwnedMount() -> Bool {
    var detached = true
    if let mount = ownedMountToDetach {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mount.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            detached = process.terminationStatus == 0
        } catch { detached = false }
        if detached { ownedMountToDetach = nil }
    }
    if detached, let root = ownedRootToClean {
        do { try FileManager.default.removeItem(at: root); ownedRootToClean = nil }
        catch { return false }
    }
    return detached
}

private func fail(_ reason: String) -> Never {
    if !cleanupOwnedMount() { fputs("owned DMG mount or scratch needs manual cleanup\n", stderr) }
    fputs("real DMG appcast proof failed: \(reason)\n", stderr)
    exit(1)
}

private func require(_ condition: Bool, _ reason: String) {
    if !condition { fail(reason) }
}

private final class AppcastReader: NSObject, XMLParserDelegate {
    var itemCount = 0
    var enclosureCount = 0
    var enclosure: [String: String] = [:]
    var version = ""
    var shortVersion = ""
    private var activeField: String?
    private var fieldText = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        if elementName == "item" { itemCount += 1 }
        if itemCount == 1 && elementName == "enclosure" {
            enclosureCount += 1
            enclosure = attributeDict
        }
        if itemCount == 1 && (elementName == "sparkle:version" ||
                              elementName == "sparkle:shortVersionString") {
            activeField = elementName
            fieldText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if activeField != nil { fieldText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if activeField == elementName {
            let value = fieldText.trimmingCharacters(in: .whitespacesAndNewlines)
            if elementName == "sparkle:version" { version = value }
            if elementName == "sparkle:shortVersionString" { shortVersion = value }
            activeField = nil
        }
    }
}

private func run(_ executable: String, _ arguments: [String]) -> (Int32, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { fail("cannot run \(executable): \(error)") }
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(data: output, encoding: .utf8) ?? "")
}

require(CommandLine.arguments.count == 6, "expected DMG, appcast, version, build, SHA-256")
let dmgURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let appcastURL = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
let expectedVersion = CommandLine.arguments[3]
let expectedBuild = CommandLine.arguments[4]
let expectedHash = CommandLine.arguments[5].lowercased()
require(expectedVersion == "0.4.0", "this proof is scoped to version 0.4.0")
require(expectedBuild.range(of: "^[1-9][0-9]*$", options: .regularExpression) != nil,
        "invalid expected build")
require(expectedHash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
        "invalid expected DMG SHA-256")
require(dmgURL.lastPathComponent == "ScreenshotTool-0.4.0-macOS.dmg", "wrong DMG name")

let dmg: Data
do { dmg = try Data(contentsOf: dmgURL) }
catch { fail("cannot read DMG: \(error)") }
require(!dmg.isEmpty, "empty DMG")
let actualHash = SHA256.hash(data: dmg).map { String(format: "%02x", $0) }.joined()
require(actualHash == expectedHash, "DMG SHA-256 differs from expected hash")

let xml: Data
do { xml = try Data(contentsOf: appcastURL) }
catch { fail("cannot read appcast: \(error)") }
private let reader = AppcastReader()
let parser = XMLParser(data: xml)
parser.shouldProcessNamespaces = false
parser.shouldResolveExternalEntities = false
parser.delegate = reader
require(parser.parse(), "invalid appcast XML: \(parser.parserError?.localizedDescription ?? "unknown error")")
require(reader.itemCount == 1 && reader.enclosureCount == 1,
        "expected exactly one item and one enclosure")
require(reader.version == expectedBuild, "appcast build mismatch")
require(reader.shortVersion == expectedVersion, "appcast version mismatch")
require(reader.enclosure["url"] == expectedURL, "unexpected download URL")
require(reader.enclosure["type"] == "application/x-apple-diskimage", "unexpected MIME type")
require(reader.enclosure["length"] == String(dmg.count), "signed length differs from DMG bytes")
guard let signatureText = reader.enclosure["sparkle:edSignature"],
      let signature = Data(base64Encoded: signatureText), signature.count == 64,
      let keyBytes = Data(base64Encoded: pinnedPublicKey), keyBytes.count == 32 else {
    fail("missing or invalid Ed25519 signature/public key")
}
let publicKey: Curve25519.Signing.PublicKey
do { publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyBytes) }
catch { fail("invalid public key: \(error)") }
require(publicKey.isValidSignature(signature, for: dmg),
        "Ed25519 signature does not verify over the exact DMG bytes")

let ownedRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("st-real-dmg-proof-\(UUID().uuidString)", isDirectory: true)
let mountURL = ownedRoot.appendingPathComponent("mount", isDirectory: true)
ownedRootToClean = ownedRoot
do {
    try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
} catch { fail("cannot create private mountpoint: \(error)") }
let (attachStatus, attachOutput) = run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse",
    "-mountpoint", mountURL.path, dmgURL.path])
require(attachStatus == 0, "cannot mount DMG read-only: \(attachOutput)")
ownedMountToDetach = mountURL

let infoURL = mountURL.appendingPathComponent("ScreenshotTool.app/Contents/Info.plist")
let infoData: Data
do { infoData = try Data(contentsOf: infoURL) }
catch { fail("cannot read packaged app Info.plist: \(error)") }
let info: [String: Any]
do {
    guard let parsed = try PropertyListSerialization.propertyList(from: infoData, format: nil)
        as? [String: Any] else { fail("invalid packaged Info.plist") }
    info = parsed
} catch { fail("invalid packaged Info.plist: \(error)") }
require(info["CFBundleShortVersionString"] as? String == expectedVersion,
        "packaged app version mismatch")
require(info["CFBundleVersion"] as? String == expectedBuild,
        "packaged app build mismatch")
require(info["SUPublicEDKey"] as? String == pinnedPublicKey,
        "packaged app public key differs from pinned installed key")
require(cleanupOwnedMount(), "owned DMG mount or scratch did not clean up")

print("real DMG appcast proof: PASS")
print("dmg_sha256=\(actualHash)")
print("dmg_length=\(dmg.count)")
print("version=\(expectedVersion)")
print("build=\(expectedBuild)")
print("public_key=\(pinnedPublicKey)")
