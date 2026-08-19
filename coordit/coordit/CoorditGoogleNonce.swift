import CryptoKit
import Foundation

struct CoorditGoogleNonce {
    let rawValue: String

    static func make() -> Self {
        Self(rawValue: UUID().uuidString)
    }

    var googleRequestValue: String {
        SHA256.hash(data: Data(rawValue.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
