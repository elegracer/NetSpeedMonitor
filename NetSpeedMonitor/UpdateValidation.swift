import CryptoKit
import Foundation

enum UpdateValidation {
    static func expectedSHA256(digest: String?, checksumText: String?) -> String? {
        if let digest, digest.hasPrefix("sha256:") {
            return String(digest.dropFirst("sha256:".count)).lowercased()
        }
        guard let checksumText else { return nil }
        return checksumText.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map { String($0).lowercased() }
    }

    static func sha256Hex(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func matchesSHA256(data: Data, expected: String) -> Bool {
        sha256Hex(data: data) == expected.lowercased()
    }
}
