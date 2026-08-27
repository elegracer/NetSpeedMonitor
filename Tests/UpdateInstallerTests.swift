import Foundation
import CryptoKit

func run(_ executable: String, _ arguments: [String], currentDirectory: URL? = nil) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "UpdateInstallerTests", code: Int(process.terminationStatus))
    }
}

func makeArchive(root: URL, tag: String, extraEntry: Bool = false) throws -> (URL, String) {
    let fileManager = FileManager.default
    let source = root.appendingPathComponent(UUID().uuidString)
    let app = source.appendingPathComponent("NetSpeedMonitor.app")
    let contents = app.appendingPathComponent("Contents")
    let executableDirectory = contents.appendingPathComponent("MacOS")
    try fileManager.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleIdentifier": "com.elegracer.NetSpeedMonitor",
        "CFBundleExecutable": "NetSpeedMonitor",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.21",
        "NetSpeedMonitorReleaseTag": tag,
    ]
    let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try plistData.write(to: contents.appendingPathComponent("Info.plist"))
    let executable = executableDirectory.appendingPathComponent("NetSpeedMonitor")
    try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path])
    if extraEntry {
        try "unexpected".write(to: source.appendingPathComponent("unexpected.txt"), atomically: true, encoding: .utf8)
    }
    let archive = root.appendingPathComponent("\(UUID().uuidString).zip")
    if extraEntry {
        try run("/usr/bin/zip", ["-qry", archive.path, "NetSpeedMonitor.app", "unexpected.txt"], currentDirectory: source)
    } else {
        try run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--keepParent", app.path, archive.path])
    }
    return (archive, try UpdateValidation.sha256Hex(fileURL: archive))
}

@main
struct UpdateInstallerTests {
    static func main() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        func releaseSignature(tag: String, digest: String) throws -> String {
            try signingKey.signature(for: ReleaseSignature.message(releaseTag: tag, sha256: digest)).base64EncodedString()
        }
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("NetSpeedMonitor-installer-tests-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let verifier: UpdateInstaller.SignatureVerifier = { signature, tag, digest in
            guard let data = Data(base64Encoded: signature) else { return false }
            return signingKey.publicKey.isValidSignature(data, for: ReleaseSignature.message(releaseTag: tag, sha256: digest))
        }
        let installer = UpdateInstaller(currentVersion: "1.20", currentReleaseTag: "v1.20", currentAppPath: "/Applications/NetSpeedMonitor.app", currentProcessID: 1, signatureVerifier: verifier)
        let valid = try makeArchive(root: root, tag: "v1.21-beta.2")
        let validSignature = try releaseSignature(tag: "v1.21-beta.2", digest: valid.1)
        let validWork = root.appendingPathComponent("valid-work")
        try fileManager.createDirectory(at: validWork, withIntermediateDirectories: true)
        let prepared = try installer.prepare(downloadedZip: valid.0, workDirectory: validWork, expectedDigest: "sha256:\(valid.1)", signatureBase64: validSignature, targetReleaseTag: "v1.21-beta.2")
        guard prepared.version == "v1.21-beta.2", fileManager.fileExists(atPath: prepared.scriptURL.path) else {
            fatalError("valid update was not prepared")
        }
        try run("/bin/bash", ["-n", prepared.scriptURL.path])

        let mismatchWork = root.appendingPathComponent("mismatch-work")
        try fileManager.createDirectory(at: mismatchWork, withIntermediateDirectories: true)
        var rejectedTagMismatch = false
        do {
            _ = try installer.prepare(downloadedZip: valid.0, workDirectory: mismatchWork, expectedDigest: "sha256:\(valid.1)", signatureBase64: validSignature, targetReleaseTag: "v1.21-beta.3")
        } catch {
            rejectedTagMismatch = true
        }
        guard rejectedTagMismatch else { fatalError("release tag mismatch was accepted") }

        let digestWork = root.appendingPathComponent("digest-work")
        try fileManager.createDirectory(at: digestWork, withIntermediateDirectories: true)
        var rejectedDigestMismatch = false
        do {
            _ = try installer.prepare(downloadedZip: valid.0, workDirectory: digestWork, expectedDigest: "sha256:\(String(repeating: "0", count: 64))", signatureBase64: validSignature, targetReleaseTag: "v1.21-beta.2")
        } catch {
            rejectedDigestMismatch = true
        }
        guard rejectedDigestMismatch else { fatalError("checksum mismatch was accepted") }

        let signatureWork = root.appendingPathComponent("signature-work")
        try fileManager.createDirectory(at: signatureWork, withIntermediateDirectories: true)
        var rejectedSignatureMismatch = false
        do {
            _ = try installer.prepare(downloadedZip: valid.0, workDirectory: signatureWork, expectedDigest: "sha256:\(valid.1)", signatureBase64: Data(repeating: 0, count: 64).base64EncodedString(), targetReleaseTag: "v1.21-beta.2")
        } catch {
            rejectedSignatureMismatch = true
        }
        guard rejectedSignatureMismatch else { fatalError("invalid release signature was accepted") }

        let unsafe = try makeArchive(root: root, tag: "v1.21", extraEntry: true)
        let unsafeWork = root.appendingPathComponent("unsafe-work")
        try fileManager.createDirectory(at: unsafeWork, withIntermediateDirectories: true)
        var rejectedUnsafeArchive = false
        do {
            let unsafeSignature = try releaseSignature(tag: "v1.21", digest: unsafe.1)
            _ = try installer.prepare(downloadedZip: unsafe.0, workDirectory: unsafeWork, expectedDigest: "sha256:\(unsafe.1)", signatureBase64: unsafeSignature, targetReleaseTag: "v1.21")
        } catch {
            rejectedUnsafeArchive = true
        }
        guard rejectedUnsafeArchive else { fatalError("archive with an unexpected top-level file was accepted") }

        print("Update installer tests passed")
    }
}
