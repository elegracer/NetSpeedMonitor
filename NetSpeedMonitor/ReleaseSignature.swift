import CryptoKit
import Foundation

enum ReleaseSignature {
    // Ed25519 public key. The matching private key is never stored in the repository.
    static let publicKeyBase64 = "uRHL9nE6ynz9+UazuQutmh2pWVobsKdOf5DEaExderg="

    static func message(releaseTag: String, sha256: String) -> Data {
        Data("NetSpeedMonitor release\n\(releaseTag)\n\(sha256.lowercased())\n".utf8)
    }

    static func verify(signatureBase64: String, releaseTag: String, sha256: String) -> Bool {
        guard let publicKeyData = Data(base64Encoded: publicKeyBase64),
              let signature = Data(base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              signature.count == 64,
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
            return false
        }
        return publicKey.isValidSignature(signature, for: message(releaseTag: releaseTag, sha256: sha256))
    }
}
