import XCTest

/// Both sign-in buttons are REACHABLE AND ENABLED in a build that carries a
/// Firebase configuration.
///
/// **This test exists because three builds in a row shipped with login broken
/// by something no source check could see**, and each time the evidence
/// offered was an inspection of an artifact rather than the app running:
///
///   - 0.7.1 build 184: Firebase linked, `GoogleService-Info.plist` never
///     copied into the archive. Settings read "no Firebase configuration".
///   - 0.7.2 build 185: Apple's capability fully provisioned -- App ID,
///     profile, embedded profile, codesigned entitlements, all verified -- and
///     the button still disabled, because the app decided its own availability
///     by reading an `embedded.mobileprovision` that an App Store-signed app
///     does not carry.
///
/// A grep says the entitlement is in the archive. It cannot say the button is
/// tappable. So this asserts the thing that actually matters, in the running
/// app, and it fails on either of those two bugs.
final class SignInReachable: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences"]
        app.launch()
    }

    /// Open Settings and find the account section.
    private func openAccount() -> Bool {
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)
        let gear = app.descendants(matching: .any)["library-settings"]
        guard gear.waitForExistence(timeout: 60) else { return false }
        gear.tap()
        // Settings is a split (0.8 §7.17): Account is a section in the index.
        let account = app.buttons["settings-account"]
        if account.waitForExistence(timeout: 30) { account.tap() }
        // The section leads with the sentence that says an account is optional.
        return app.descendants(matching: .any)["account-explains-optional"]
            .waitForExistence(timeout: 30)
    }

    func testBothSignInButtonsExistAndAreEnabled() throws {
        XCTAssertTrue(openAccount(), "the account section never appeared")

        // If this build carries no Firebase config the section says so, and
        // that is a DIFFERENT failure worth naming rather than a missing
        // button -- it is exactly what 184 shipped.
        let unconfigured = app.descendants(matching: .any)["account-unavailable"]
        XCTAssertFalse(unconfigured.exists,
                       "this build has no Firebase configuration, so sign-in "
                       + "is disabled before either button is even considered "
                       + "-- 0.7.1 build 184's bug")

        for id in ["sign-in-google", "sign-in-apple"] {
            let button = app.descendants(matching: .any)[id]
            XCTAssertTrue(button.waitForExistence(timeout: 20), "\(id) is missing")
            XCTAssertTrue(button.isEnabled,
                          "\(id) exists but is DISABLED -- 0.7.2 build 185's "
                          + "bug, where the app gated a provisioned capability "
                          + "on reading its own provisioning profile")
            XCTAssertTrue(button.isHittable, "\(id) is not tappable")
        }

        // And the excuse that used to sit under a disabled Apple button must
        // be gone, because there is nothing left that can produce it.
        XCTAssertFalse(app.descendants(matching: .any)["account-apple-unavailable"].exists,
                       "the app still claims Apple sign-in needs a capability "
                       + "it does not have")
    }

    /// A failure is VISIBLE. Never an endless "Signing in…".
    ///
    /// **What a simulator can and cannot prove, stated so nobody re-litigates
    /// it.** Completing Sign in with Apple needs an Apple ID signed into the
    /// device; a bare simulator has none and no test may type credentials. So
    /// the sheet appearing is Ali's device to verify.
    ///
    /// What IS provable here is the property that was broken: a tap resolves.
    /// `-failAppleSignIn` forces the failure path, and this asserts the reader
    /// is told -- which is exactly what did not happen when the controller was
    /// released before answering and the app sat spinning for ever.
    func testAFailedAppleSignInSaysSoInsteadOfSpinning() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences",
                               "-failAppleSignIn"]
        app.launch()
        XCTAssertTrue(openAccount(), "the account section never appeared")

        let apple = app.descendants(matching: .any)["sign-in-apple"]
        XCTAssertTrue(apple.waitForExistence(timeout: 20))
        apple.tap()

        let error = app.descendants(matching: .any)["account-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 20),
                      "a failed Apple sign-in showed no error at all -- the "
                      + "reader is left with a button that did nothing")
        XCTAssertFalse(app.staticTexts["Signing in…"].exists,
                       "still spinning after the failure was reported")
    }

    /// And the timeout itself fires, on its own, with nothing to answer it.
    ///
    /// `-appleSignInPatience 3` shortens the real 20s. Without a firing
    /// timeout, an unanswered request is an infinite spinner -- which is what
    /// 0.7.2 build 185 shipped.
    func testAnUnansweredRequestTimesOutRatherThanSpinningForEver() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences",
                               "-appleSignInPatience", "3"]
        app.launch()
        XCTAssertTrue(openAccount(), "the account section never appeared")

        let apple = app.descendants(matching: .any)["sign-in-apple"]
        XCTAssertTrue(apple.waitForExistence(timeout: 20))
        apple.tap()

        // Well past the 3s patience. Either Apple answered (a sheet, on a
        // machine with an Apple ID) or the timeout did -- and in neither case
        // may it still be spinning.
        let deadline = Date().addingTimeInterval(25)
        var spinning = true
        while Date() < deadline {
            if !app.staticTexts["Signing in…"].exists { spinning = false; break }
            usleep(400_000)
        }
        XCTAssertFalse(spinning,
                       "still \"Signing in…\" 25s after a tap with a 3s "
                       + "patience: the timeout did not fire, so an "
                       + "unanswered request has no way out")
    }
}
