import XCTest

/// Chat brings its own key (0.15.0; Ali, 2026-09-23): the reader's saved
/// OpenRouter key or none, and never the developer's -- which through 0.14.0
/// was baked into every build, and which the old 401 "self-heal" wrote into
/// readers' Keychains as though they had typed it.
final class ChatKeyTests: XCTestCase {

    private let own = "sk-or-v1-0123456789abcdef0123456789abcdef"

    func testNoSavedKeyMeansNoChatKey() {
        XCTAssertEqual(ChatKey.choose(saved: ""), .missing,
                       "there is no built-in key to fall back to any more")
        XCTAssertEqual(ChatKey.choose(saved: "  \n "), .missing)
    }

    func testTheReadersOwnKeyIsUsedAsSaved() {
        XCTAssertEqual(ChatKey.choose(saved: own), .use(own))
        XCTAssertEqual(ChatKey.choose(saved: "  \(own)\n"), .use(own),
                       "a pasted key's stray whitespace is not part of it")
    }

    /// The developer key the self-heal left behind counts as no key at all.
    /// No test can carry the real one, so a stand-in is retired by its hash.
    func testARetiredKeyLeftInTheKeychainCountsAsMissing() {
        let leftBehind = "sk-or-v1-developers-key-a-device-was-given-unasked"
        let retired: Set<String> = [RetiredKeys.sha256Hex(leftBehind)]
        XCTAssertEqual(ChatKey.choose(saved: leftBehind, retired: retired), .missing)
        XCTAssertEqual(ChatKey.choose(saved: own, retired: retired), .use(own),
                       "only the retired key is refused, not the reader's")
        XCTAssertTrue(RetiredKeys.isRetiredOpenRouterKey("  \(leftBehind) ", retired: retired))
        XCTAssertFalse(RetiredKeys.isRetiredOpenRouterKey("", retired: retired))
    }

    /// The hash is of the key and nothing else: stable, hex, 64 characters.
    func testTheHashIsTheStandardSHA256() {
        XCTAssertEqual(RetiredKeys.sha256Hex("abc"),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(RetiredKeys.openRouterSHA256.count, 1)
        XCTAssertTrue(RetiredKeys.openRouterSHA256.allSatisfy {
            $0.count == 64 && $0.allSatisfy(\.isHexDigit)
        })
    }

    /// What a musician is told: what is needed, where to get it, where it goes.
    func testTheSentencesSayWhereAKeyComesFromAndWhereItGoes() {
        for sentence in [ChatKey.missingSentence, ChatKey.rejectedSentence] {
            XCTAssertTrue(sentence.contains("openrouter.ai/keys"), sentence)
            XCTAssertTrue(sentence.contains("Settings › Engine"), sentence)
            XCTAssertFalse(sentence.lowercased().contains("baked"),
                           "written for a developer, not a reader: \(sentence)")
        }
    }

    /// Settings says which key is in use -- testSettingsFieldsAreLabelled reads
    /// "no key" or "your key" off the page.
    func testSettingsSaysWhichKeyIsInUse() {
        let none = ChatKey.status(saved: "")
        XCTAssertTrue(none.lowercased().contains("no key"), none)
        XCTAssertTrue(none.contains("openrouter.ai/keys"), none)
        let mine = ChatKey.status(saved: own)
        XCTAssertTrue(mine.contains("Using your key"), mine)
        XCTAssertTrue(mine.contains("…cdef"), "the last four, and only those: \(mine)")
        XCTAssertFalse(mine.contains(own), "the whole key is never shown")
        XCTAssertFalse(mine.lowercased().contains("built-in"),
                       "there is no built-in key to fall back to: \(mine)")
    }
}
