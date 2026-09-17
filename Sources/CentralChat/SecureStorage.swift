import Foundation
import Security

/**
 Where the chat's session token and encryption keys live on this device.

 The Keychain rather than the web view's own storage, and that is the entire
 point of it: web view data is the app's to delete — a "clear app data", an
 app's own cache button — and history is encrypted to devices, so dropping the
 keys does not merely sign the visitor out, it makes their thread unreadable.
 The Keychain survives all of that, and `ThisDeviceOnly` keeps it off iCloud
 and out of an encrypted backup restored onto somebody else's phone.

 Every method runs on the bridge's own queue, never the main one.
 */
enum SecureStorage {

    private static let service = "chat.central.widget.storage"

    static func get(_ key: String) -> String? {
        var query = base(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ key: String, _ value: String) throws {
        let data = Data(value.utf8)
        // Update-then-add rather than delete-then-add: a delete that succeeds
        // and an add that fails would lose a session token that was fine.
        let updated = SecItemUpdate(
            base(key) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw failure(updated) }

        var insert = base(key)
        insert[kSecValueData as String] = data
        // ThisDeviceOnly: never synced to iCloud, never restored onto another
        // device. A device's encryption keys belong to that device alone.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(insert as CFDictionary, nil)
        guard added == errSecSuccess else { throw failure(added) }
    }

    static func remove(_ key: String) throws {
        let status = SecItemDelete(base(key) as CFDictionary)
        // Deleting what is not there is the outcome the caller asked for.
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }

    /**
     The adapter's contract is FULL keys, so what went in is what comes back.

     `kSecAttrAccount` holds the key verbatim, so unlike Android this needs no
     manifest of its own — the Keychain enumerates its own service.
     */
    static func list(prefix: String) -> [String] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        query[kSecReturnData as String] = false
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
              let rows = items as? [[String: Any]] else { return [] }
        return rows.compactMap { $0[kSecAttrAccount as String] as? String }
            .filter { $0.hasPrefix(prefix) }
    }

    private static func base(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    private static func failure(_ status: OSStatus) -> NSError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "keychain error \(status)"
        return NSError(domain: "chat.central.widget.storage", code: Int(status),
                       userInfo: [NSLocalizedDescriptionKey: message])
    }
}
