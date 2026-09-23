import Foundation

/// Which OpenRouter key chat may use: the reader's own, or none.
///
/// Chat brings its own key from 0.15.0 (Ali, 2026-09-23). Through 0.14.0 the
/// developer's key was baked into every build and used whenever the reader had
/// saved none -- so every copy of the app, anywhere, spent that one account,
/// and the key was readable by anyone who unzipped the .ipa. Now the only key
/// is the one the reader pastes in Settings, and the reader's own OpenRouter
/// account is what the chat is billed to and what its privacy settings are.
///
/// Pure, so the rule is tested without a network: LocalChat asks this, and
/// Settings says the same thing in the same words.
enum ChatKey {

    enum Choice: Equatable {
        case use(String)
        case missing
    }

    /// The reader's saved key, or `.missing`. A retired developer key counts as
    /// missing even if the old self-heal left it in the Keychain -- see
    /// `RetiredKeys`.
    static func choose(saved: String,
                       retired: Set<String> = RetiredKeys.openRouterSHA256) -> Choice {
        let key = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty || RetiredKeys.isRetiredOpenRouterKey(key, retired: retired) {
            return .missing
        }
        return .use(key)
    }

    /// Where a reader gets a key. Named once, so the chat and Settings agree.
    static let keysPage = "openrouter.ai/keys"

    /// What chat says with no key. For a musician, not a developer: what is
    /// needed, where it comes from, where it goes.
    static let missingSentence =
        "Chat uses your own OpenRouter account. Make a key at \(keysPage), "
        + "then paste it in Settings › Engine."

    /// What chat says when OpenRouter refuses the saved key.
    static let rejectedSentence =
        "OpenRouter turned down the key saved in Settings. Check it at "
        + "\(keysPage) -- it may have been revoked or run out of credit -- "
        + "and paste a working one in Settings › Engine."

    /// Settings, under the key field.
    static func status(saved: String) -> String {
        switch choose(saved: saved) {
        case .use(let key):
            return "Using your key (…\(String(key.suffix(4)))). Chat is billed to your "
                + "OpenRouter account. Type a new one to replace it, or Clear to remove it."
        case .missing:
            return "No key yet. Chat uses your own OpenRouter account: make a key at "
                + "\(keysPage) and paste it here."
        }
    }
}
