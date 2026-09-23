import CryptoKit
import Foundation

/// Keys that must never be used again, known only by their SHA-256.
///
/// Through 0.14.0 the developer's own OpenRouter key was baked into every
/// build as openrouter-default-key.txt, and chat fell back to it -- and on a
/// 401 from a key the reader had saved, `LocalChat` SILENTLY WROTE THE BAKED
/// KEY INTO THE READER'S KEYCHAIN in its place ("self-heal"). So a device that
/// ever hit that path holds the developer's key as though its reader had typed
/// it, and removing the key from the build does not remove it from there.
///
/// From 0.15.0 chat uses the reader's own key and the app ships none (Ali,
/// 2026-09-23). This is how a device forgets the retired one: at launch, a
/// saved key whose hash is listed here is cleared, and chat asks for the
/// reader's own. A hash reveals nothing about the key, so this is safe to
/// commit to a public repository; the value itself is in no file the app
/// carries.
///
/// The one listed is the key builds 201-203 carried: 73 characters, hashed
/// from the .env those builds were made from, after the old bake step's own
/// normalisation (quotes and whitespace stripped).
///
/// Belt and braces, not the fix: the fix is revoking that key in OpenRouter,
/// which kills every copy -- in old .ipa files as well as in Keychains.
enum RetiredKeys {

    static let openRouterSHA256: Set<String> = [
        "cdb49f6a5f5c39b4a1f60e88747dcb67bc648fd46e2c25bcebb53d64cdd0aadb",
    ]

    /// `retired` is the list to check against; a test hands in its own,
    /// because no test can carry the real key.
    static func isRetiredOpenRouterKey(_ key: String,
                                       retired: Set<String> = openRouterSHA256) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return retired.contains(sha256Hex(trimmed))
    }

    static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
