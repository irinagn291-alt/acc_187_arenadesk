import Foundation
import CryptoKit

enum PINHasher {
    static func hash(pin: String, salt: String) -> String {
        let input = Data((salt + pin).utf8)
        let digest = SHA256.hash(data: input)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func makeSalt() -> String {
        UUID().uuidString.lowercased()
    }

    static func verify(pin: String, hash: String, salt: String) -> Bool {
        Self.hash(pin: pin, salt: salt) == hash
    }
}
