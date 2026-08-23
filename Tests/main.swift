import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Test failed: \(message)\n", stderr)
        exit(1)
    }
}

expect(AppSettings.updateIntervals == [1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60], "update interval presets")
expect(AppSettings.normalizedUpdateInterval(0) == 1, "zero interval migration")
expect(AppSettings.normalizedUpdateInterval(7) == 5, "custom interval migration")
expect(AppSettings.normalizedUpdateInterval(55) == 50, "tie uses lower interval")
expect(AppSettings.compareVersions("1.9", "1.10") == .orderedAscending, "numeric version comparison")
expect(AppSettings.compareVersions("1.12", "1.12") == .orderedSame, "equal version comparison")
expect(AppSettings.maximumSampleAge(for: 60) == 90, "60-second sample tolerance")
expect(UpdateValidation.expectedSHA256(digest: "sha256:ABC123", checksumText: nil) == "abc123", "GitHub digest parsing")
expect(UpdateValidation.expectedSHA256(digest: nil, checksumText: "DEF456  NetSpeedMonitor.zip\n") == "def456", "checksum file parsing")
expect(UpdateValidation.sha256Hex(data: Data("test".utf8)) == "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08", "SHA256 calculation")
expect(!UpdateValidation.matchesSHA256(data: Data("tampered".utf8), expected: String(repeating: "0", count: 64)), "SHA256 mismatch rejection")

print("Swift logic tests passed")
