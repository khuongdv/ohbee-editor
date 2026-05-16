import CryptoKit
import Foundation

public enum ChecksumTools {
    public static func sha256(of text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func md5(of text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
