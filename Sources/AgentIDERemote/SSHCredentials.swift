import Crypto
import Foundation
import NIOSSH
import Security

// MARK: - SSHCredentials

/// Device credentials and host-key pins, never stored in app preferences.
public enum SSHCredentials {
    // MARK: Public

    /// Exports the device’s Ed25519 public key in authorised_keys format.
    public static func publicKey() throws -> String {
        try String(openSSHPublicKey: NIOSSHPrivateKey(ed25519Key: privateKey()).publicKey) + " AgentIDE-iPhone"
    }

    /// Pins a verified host key for this host and port.
    public static func trust(_ key: String, for identity: String) throws {
        try save(Data(key.utf8), account: "host:" + identity)
    }

    /// Removes a host pin after the user has verified a changed key.
    public static func forgetHost(_ identity: String) throws {
        let status = SecItemDelete(query("host:" + identity) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RemoteError("Could not remove the saved host key (" + String(status) + ").")
        }
    }

    /// Formats the SHA-256 fingerprint used by OpenSSH.
    public static func fingerprint(_ key: String) -> String {
        let encoded = key.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        guard let data = Data(base64Encoded: encoded) else {
            return key
        }

        return "SHA256:" + Data(SHA256.hash(data: data)).base64EncodedString().replacing("=", with: "")
    }

    // MARK: Internal

    static func privateKey(
        read: () throws -> Data? = { try Self.read("identity") },
        insert: (Data) -> OSStatus = { Self.add($0, account: "identity") },
    ) throws -> Curve25519.Signing.PrivateKey {
        if let data = try read() {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        }
        let key = Curve25519.Signing.PrivateKey()
        let added = insert(key.rawRepresentation)
        if added == errSecDuplicateItem, let data = try read() {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        }
        guard added == errSecSuccess else {
            throw RemoteError("Could not save the SSH key (" + String(added) + ").")
        }

        return key
    }

    static func hostKey(for identity: String) throws -> String? {
        try read("host:" + identity).flatMap { String(data: $0, encoding: .utf8) }
    }

    // MARK: Private

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.mikemcquaid.AgentIDE.ssh",
            kSecAttrAccount as String: account,
        ]
    }

    private static func read(_ account: String) throws -> Data? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = unsafe SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw RemoteError("Could not read the SSH key from Keychain (" + String(status) + ").")
        }

        return data
    }

    private static func save(_ data: Data, account: String) throws {
        let request = query(account)
        let status = SecItemUpdate(request as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else {
            throw RemoteError("Could not update the SSH key (" + String(status) + ").")
        }

        let added = add(data, account: account)
        guard added == errSecSuccess else {
            throw RemoteError("Could not save the SSH key (" + String(added) + ").")
        }
    }

    private static func add(_ data: Data, account: String) -> OSStatus {
        var addition = query(account)
        addition[kSecValueData as String] = data
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(addition as CFDictionary, nil)
    }
}

// MARK: - SSHHostKeyError

/// Host verification requires a decision before authentication proceeds.
public enum SSHHostKeyError: Error, LocalizedError {
    case unknown(String)
    case changed

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case .unknown:
            "Confirm this Mac's SSH host key before connecting."

        case .changed:
            "The Mac's SSH host key has changed. Verify it, then forget the saved key in Settings."
        }
    }
}
