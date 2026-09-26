import Foundation
import Security

struct StoredCredentials: Codable, Sendable {
    let studentID: String
    let password: String
}

actor KeychainVault {
    static let shared = KeychainVault()
    private let service = "org.openahu.ahutong.macos.credentials"
    private let account = "wisdom-ahu"

    func load() throws -> StoredCredentials? {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CampusClientError.security("无法读取钥匙串（\(status)）")
        }
        return try JSONDecoder().decode(StoredCredentials.self, from: data)
    }

    func save(_ credentials: StoredCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let update = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else {
            throw CampusClientError.security("无法更新钥匙串（\(update)）")
        }
        var item = baseQuery
        attributes.forEach { item[$0.key] = $0.value }
        let add = SecItemAdd(item as CFDictionary, nil)
        guard add == errSecSuccess else {
            throw CampusClientError.security("无法保存钥匙串（\(add)）")
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CampusClientError.security("无法清除钥匙串（\(status)）")
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
