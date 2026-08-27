#!/usr/bin/env swift

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 4 else {
    fail("Usage: sign-release.swift <private-key-base64-file> <release-tag> <zip-path>")
}

let keyFile = URL(fileURLWithPath: CommandLine.arguments[1])
let releaseTag = CommandLine.arguments[2]
let zipURL = URL(fileURLWithPath: CommandLine.arguments[3])
let encodedKey = try String(contentsOf: keyFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
guard let keyData = Data(base64Encoded: encodedKey), keyData.count == 32 else { fail("Invalid Ed25519 private key") }
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
let handle = try FileHandle(forReadingFrom: zipURL)
defer { try? handle.close() }
var hasher = SHA256()
while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hasher.update(data: chunk) }
let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
let message = Data("NetSpeedMonitor release\n\(releaseTag)\n\(digest)\n".utf8)
let signature = try key.signature(for: message).base64EncodedString()
try (signature + "\n").write(to: zipURL.deletingLastPathComponent().appendingPathComponent("NetSpeedMonitor.sig"), atomically: true, encoding: .utf8)
