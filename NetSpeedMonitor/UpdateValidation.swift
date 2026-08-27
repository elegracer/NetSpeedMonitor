import CryptoKit
import Foundation

enum UpdateValidation {
    static func expectedSHA256(digest: String?, checksumText: String?) -> String? {
        let candidate: String?
        if let digest, digest.hasPrefix("sha256:") {
            candidate = String(digest.dropFirst("sha256:".count)).lowercased()
        } else {
            candidate = checksumText?.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map { String($0).lowercased() }
        }
        guard let candidate, candidate.count == 64, candidate.allSatisfy({ $0.isHexDigit }) else { return nil }
        return candidate
    }

    static func sha256Hex(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func matchesSHA256(data: Data, expected: String) -> Bool {
        sha256Hex(data: data) == expected.lowercased()
    }

    static func sha256Hex(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func matchesSHA256(fileURL: URL, expected: String) throws -> Bool {
        try sha256Hex(fileURL: fileURL) == expected.lowercased()
    }
}
