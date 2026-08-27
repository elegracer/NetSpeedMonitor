import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Test failed: \(message)\n", stderr)
        exit(1)
    }
}

expect(AppSettings.updateIntervals == [1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60], "update interval presets")
expect(AppSettings.normalizedUpdateChannel(nil) == .stable, "default update channel")
expect(AppSettings.normalizedUpdateChannel("prerelease") == .prerelease, "prerelease update channel")
expect(AppSettings.normalizedUpdateChannel("invalid") == .stable, "invalid update channel migration")
expect(!AppSettings.normalizedIntegerSmallUnits(nil), "default integer small-unit setting")
expect(AppSettings.normalizedIntegerSmallUnits(true), "enabled integer small-unit setting")
expect(AppSettings.normalizedDisplayMode(nil) == .both, "default display mode")
expect(AppSettings.normalizedUnitMode("bitsDecimal") == .bitsDecimal, "bit unit mode")
expect(AppSettings.appVersion(fromReleaseTag: "v1.18-beta.1") == "1.18", "pre-release tag app version")
expect(AppSettings.newestReleaseTag(from: ["v1.17", "v1.18-beta.1"], includePrereleases: false) == "v1.17", "stable channel ignores prerelease tags")
expect(AppSettings.newestReleaseTag(from: ["v1.17", "v1.18-beta.1"], includePrereleases: true) == "v1.18-beta.1", "prerelease channel includes prerelease tags")
expect(AppSettings.newestReleaseTag(from: ["v1.18", "v1.18-beta.1"], includePrereleases: true) == "v1.18", "stable release wins over same-version prerelease")
expect(AppSettings.newestReleaseTag(from: ["v1.18-beta.1", "v1.18-beta.2"], includePrereleases: true) == "v1.18-beta.2", "newer prerelease suffix wins")
expect(AppSettings.compareVersions("v1.21-beta.1", "v1.21-beta.2") == .orderedAscending, "prerelease sequence comparison")
expect(AppSettings.compareVersions("v1.21-rc.1", "v1.21") == .orderedAscending, "stable release follows prerelease")
expect(AppSettings.compareVersions("1.21", "1.21.0") == .orderedSame, "missing core components compare as zero")
expect(AppSettings.formattedSpeed(bytesPerSecond: 512, integerSmallUnits: false) == "512.00  B/s", "B/s keeps decimals by default")
expect(AppSettings.formattedSpeed(bytesPerSecond: 512, integerSmallUnits: true) == "   512  B/s", "B/s integer formatting")
expect(AppSettings.formattedSpeed(bytesPerSecond: 1001, integerSmallUnits: false) == "1001.00  B/s", "binary unit threshold")
expect(AppSettings.formattedSpeed(bytesPerSecond: 1024, integerSmallUnits: false) == "  1.00 KB/s", "KB starts at 1024 bytes")
expect(AppSettings.formattedSpeed(bytesPerSecond: 125_000, integerSmallUnits: false, unitMode: .bitsDecimal) == "  1.00 Mb/s", "decimal bit formatting")
expect(AppSettings.formattedSpeed(bytesPerSecond: 123_456, integerSmallUnits: true) == "   121 KB/s", "KB/s integer formatting rounds")
expect(AppSettings.formattedSpeed(bytesPerSecond: 1_048_576, integerSmallUnits: true) == "  1.00 MB/s", "MB/s keeps decimals")
expect(AppSettings.normalizedUpdateInterval(0) == 1, "zero interval migration")
expect(AppSettings.normalizedUpdateInterval(7) == 5, "custom interval migration")
expect(AppSettings.normalizedUpdateInterval(55) == 50, "tie uses lower interval")
expect(AppSettings.compareVersions("1.9", "1.10") == .orderedAscending, "numeric version comparison")
expect(AppSettings.compareVersions("1.12", "1.12") == .orderedSame, "equal version comparison")
expect(AppSettings.maximumSampleAge(for: 60) == 90, "60-second sample tolerance")
let validDigest = String(repeating: "a", count: 64)
expect(UpdateValidation.expectedSHA256(digest: "sha256:\(validDigest.uppercased())", checksumText: nil) == validDigest, "GitHub digest parsing")
expect(UpdateValidation.expectedSHA256(digest: nil, checksumText: "\(validDigest.uppercased())  NetSpeedMonitor.zip\n") == validDigest, "checksum file parsing")
expect(UpdateValidation.expectedSHA256(digest: "sha256:ABC123", checksumText: nil) == nil, "short digest rejection")
expect(UpdateValidation.expectedSHA256(digest: "sha256:\(String(repeating: "z", count: 64))", checksumText: nil) == nil, "non-hex digest rejection")
expect(UpdateValidation.sha256Hex(data: Data("test".utf8)) == "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08", "SHA256 calculation")
let temporaryFile = FileManager.default.temporaryDirectory.appendingPathComponent("NetSpeedMonitor-validation-\(UUID().uuidString)")
try Data("test".utf8).write(to: temporaryFile)
defer { try? FileManager.default.removeItem(at: temporaryFile) }
let fileDigest = try UpdateValidation.sha256Hex(fileURL: temporaryFile)
expect(fileDigest == "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08", "streaming SHA256 calculation")
expect(!UpdateValidation.matchesSHA256(data: Data("tampered".utf8), expected: String(repeating: "0", count: 64)), "SHA256 mismatch rejection")
expect(!ReleaseSignature.verify(signatureBase64: Data(repeating: 0, count: 64).base64EncodedString(), releaseTag: "v1.21", sha256: validDigest), "invalid release signature rejection")
let signatureVector = "oZjgtQd/fAslkjSdHrokxWw2fSVOt79e5wzVSfoXccBHLG7g2BwGnbYydacRpumEOHnZDYRgLqP1Y3DqX3rTBA=="
let vectorDigest = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
expect(ReleaseSignature.verify(signatureBase64: signatureVector, releaseTag: "v9.9-test.1", sha256: vectorDigest), "known release signature vector")
expect(!ReleaseSignature.verify(signatureBase64: signatureVector, releaseTag: "v9.9-test.2", sha256: vectorDigest), "signed tag tamper rejection")

print("Swift logic tests passed")
