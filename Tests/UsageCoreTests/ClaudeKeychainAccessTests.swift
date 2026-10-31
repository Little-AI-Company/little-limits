import Foundation
import Security
import Testing
@testable import UsageCore

@Test func backgroundKeychainAccessDisallowsInteractionAndRestoresItAfterFailure() throws {
    // Inspect only this test process's UI policy; never read or alter a Keychain item.
    var original = DarwinBoolean(false)
    #expect(SecKeychainGetUserInteractionAllowed(&original) == errSecSuccess)
    let returned = try ClaudeKeychainAccess.withPromptsSuppressed(unless: false) {
        var allowed = DarwinBoolean(true)
        #expect(SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess)
        #expect(!allowed.boolValue)
        return 42
    }
    #expect(returned == 42)
    var restored = DarwinBoolean(false)
    #expect(SecKeychainGetUserInteractionAllowed(&restored) == errSecSuccess)
    #expect(restored.boolValue == original.boolValue)

    #expect(throws: UsageError.self) {
        try ClaudeKeychainAccess.withPromptsSuppressed(unless: false) {
            throw UsageError.providerFailure("Expected operation failure.")
        }
    }
    #expect(SecKeychainGetUserInteractionAllowed(&restored) == errSecSuccess)
    #expect(restored.boolValue == original.boolValue)
    try ClaudeKeychainAccess.withPromptsSuppressed(unless: true) {
        var allowed = DarwinBoolean(false)
        #expect(SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess)
        #expect(allowed.boolValue == original.boolValue)
    }
}
