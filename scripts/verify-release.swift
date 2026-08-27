#!/usr/bin/env swift

import CryptoKit
import Foundation

let publicKeyBase64 = "uRHL9nE6ynz9+UazuQutmh2pWVobsKdOf5DEaExderg="

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 4 else {
    fail("Usage: verify-release.swift <release-tag> <zip-path> <signature-path>")
}
let tag = CommandLine.arguments[1]
let zipURL = URL(fileURLWithPath: CommandLine.arguments[2])
let signatureURL = URL(fileURLWithPath: CommandLine.arguments[3])
guard let publicKeyData = Data(base64Encoded: publicKeyBase64),
      let signature = Data(base64Encoded: try String(contentsOf: signatureURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) else {
    fail("Invalid public key or signature")
}
let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
let handle = try FileHandle(forReadingFrom: zipURL)
defer { try? handle.close() }
var hasher = SHA256()
while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hasher.update(data: chunk) }
let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
let message = Data("NetSpeedMonitor release\n\(tag)\n\(digest)\n".utf8)
guard key.isValidSignature(signature, for: message) else { fail("Release signature verification failed") }
print("Release signature verified: \(tag) \(digest)")
