import Foundation
import Security

#if os(iOS)
struct CoorditBackendTokenStore {
    private let service = "app.coordit.backend"
    private let account = "auth-session"

    func load() -> CoorditAuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        guard let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(CoorditAuthSession.self, from: data)
    }

    func save(_ session: CoorditAuthSession) throws {
        let data = try JSONEncoder().encode(session)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw TokenStoreError.unavailable }

        var newItem = baseQuery
        attributes.forEach { key, value in newItem[key] = value }
        guard SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess else {
            throw TokenStoreError.unavailable
        }
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum TokenStoreError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "로그인 정보를 안전하게 저장하지 못했어요."
    }
}
#endif
