import Foundation
import Security

// A disposable keychain exercises the same file-based API as CredentialStore.
// Disable authorization UI so an unexpected prompt becomes a test failure.
SecKeychainSetUserInteractionAllowed(false)
var keychain: SecKeychain?
let opened = SecKeychainOpen(CommandLine.arguments[2], &keychain)
guard opened == errSecSuccess, let keychain else { exit(1) }
let identity: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "dev.ruri.signing-probe",
    kSecAttrAccount as String: "fixture"
]
if CommandLine.arguments[1] == "create" {
    var add = identity
    add[kSecUseKeychain as String] = keychain
    add[kSecValueData as String] = Data("test credential".utf8)
    let result = SecItemAdd(add as CFDictionary, nil)
    guard result == errSecSuccess else { print("create failed: \(result)"); exit(1) }
}
var query = identity
query[kSecMatchSearchList as String] = [keychain]
query[kSecReturnData as String] = true
query[kSecMatchLimit as String] = kSecMatchLimitOne
var result: CFTypeRef?
let status = SecItemCopyMatching(query as CFDictionary, &result)
if CommandLine.arguments[1] == "deny" {
    guard status == errSecInteractionNotAllowed || status == errSecAuthFailed else {
        print("unexpected access result: \(status)"); exit(1)
    }
} else {
    guard status == errSecSuccess, result as? Data == Data("test credential".utf8) else {
        print("read failed: \(status)"); exit(1)
    }
}
