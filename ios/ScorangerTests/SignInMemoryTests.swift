import XCTest

/// The one bit that decides whether launch brings Firebase up.
///
/// Every launch asked Ali to sign in again, because the app kept principle 1
/// (no Firebase contact signed out) by never configuring Firebase at launch,
/// and so never read the session Firebase had kept. This bit is how the two
/// are reconciled, so its three transitions are pinned here.
final class SignInMemoryTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "SignInMemoryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testAFreshDeviceHasNeverSignedIn() {
        // The principle's case: nothing set, so launch touches nothing.
        XCTAssertFalse(SignInMemory(defaults: defaults).hasSignedInBefore)
    }

    func testSigningInIsRemembered() {
        let memory = SignInMemory(defaults: defaults)
        memory.remember()
        XCTAssertTrue(memory.hasSignedInBefore)
    }

    func testSigningOutIsForgottenSoTheNextLaunchStaysOut() {
        let memory = SignInMemory(defaults: defaults)
        memory.remember()
        memory.forget()
        XCTAssertFalse(memory.hasSignedInBefore)
    }

    func testTheBitOutlivesTheObjectThatSetIt() {
        // A launch is a new SignIn, and therefore a new SignInMemory.
        SignInMemory(defaults: defaults).remember()
        XCTAssertTrue(SignInMemory(defaults: defaults).hasSignedInBefore)
    }
}
