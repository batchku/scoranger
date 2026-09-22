import XCTest

/// What the reader is told before they delete their account.
///
/// Apple's App Review guideline 5.1.1(v) makes the deletion path mandatory;
/// design/FIREBASE.md §6.6 decides what it does. This pins the half that is
/// on this device: which fate each shared set list has, and the sentence that
/// says so in front of a red button.
///
/// The risk being covered is not a crash. It is a confirm that says "nothing
/// of anybody else's is affected" while the server is about to destroy a set
/// list, or the reverse -- a warning that frightens somebody out of deleting
/// an account they wanted gone. The server's half of the same rule is in
/// `firebase/succession.test.mjs` and `firebase/functions.test.mjs`.
final class AccountDeletionPlanTests: XCTestCase {

    private func mine(_ name: String, members: Int) -> AccountDeletionPlan.Standing {
        AccountDeletionPlan.Standing(name: name, isOwner: true, memberCount: members)
    }
    private func theirs(_ name: String, members: Int = 3) -> AccountDeletionPlan.Standing {
        AccountDeletionPlan.Standing(name: name, isOwner: false, memberCount: members)
    }

    // MARK: - the fate of each set list

    func testASetListOfMineWithOtherPeopleInItIsHandedOn() {
        // §6.6, and the whole point of it: deleting other people's music as a
        // side effect of leaving is the worst available outcome.
        XCTAssertEqual(AccountDeletionPlan.fate(of: mine("Friday", members: 3)), .handedOn)
        XCTAssertEqual(AccountDeletionPlan.fate(of: mine("Friday", members: 2)), .handedOn)
    }

    func testASetListOfMineThatNobodyElseIsInIsDestroyed() {
        // `memberCount` counts me, so 1 is nobody else. There is no other
        // person's work in it to protect.
        XCTAssertEqual(AccountDeletionPlan.fate(of: mine("Practice", members: 1)), .destroyed)
    }

    func testSomebodyElsesSetListIsOnlyLeft() {
        XCTAssertEqual(AccountDeletionPlan.fate(of: theirs("The band's")), .left)
        // Even if I am somehow the only one in it -- it is still not mine to
        // destroy, and the client must not say it will be.
        XCTAssertEqual(AccountDeletionPlan.fate(of: theirs("Odd", members: 1)), .left)
    }

    func testAMemberCountThatCannotHappenDoesNotDestroyAnything() {
        // A set list I own with zero members is a contradiction. The safe
        // answer is the one that does not promise to delete somebody's music,
        // and `destroyed` is only reached by OWNING the last place in it.
        XCTAssertEqual(AccountDeletionPlan.fate(of: mine("Broken", members: 0)), .destroyed)
        XCTAssertEqual(AccountDeletionPlan.fate(of: theirs("Broken", members: 0)), .left)
    }

    func testTheOutcomeSortsEverySetListIntoExactlyOneFate() {
        let outcome = AccountDeletionPlan.outcome(for: [
            mine("Friday", members: 4),
            mine("Practice", members: 1),
            theirs("The band's"),
            mine("Duo", members: 2),
        ])
        XCTAssertEqual(outcome.handedOn, ["Friday", "Duo"])
        XCTAssertEqual(outcome.destroyed, ["Practice"])
        XCTAssertEqual(outcome.left, ["The band's"])
    }

    func testSomebodyWithNoSharedSetListsHasAnEmptyOutcome() {
        XCTAssertTrue(AccountDeletionPlan.outcome(for: []).isEmpty)
    }

    // MARK: - the sentence in front of the button

    func testTheConfirmNamesTheSetListThatIsAboutToBeDestroyed() {
        // A reader is entitled to see the NAME before they press a red button.
        let said = AccountDeletionPlan.consequence(
            for: AccountDeletionPlan.outcome(for: [mine("Practice", members: 1)]))
        XCTAssertTrue(said.contains("Practice is deleted"), said)
        XCTAssertTrue(said.contains("nobody else is in it"), said)
        XCTAssertTrue(said.contains("cannot be undone"), said)
    }

    func testDestructionIsSaidFirst() {
        // It is the only irreversible loss of anybody's music in the list, and
        // the one thing a person might stop for.
        let said = AccountDeletionPlan.consequence(
            for: AccountDeletionPlan.outcome(for: [
                mine("Friday", members: 3), mine("Practice", members: 1),
            ]))
        let destroyed = said.range(of: "Practice is deleted")
        let handed = said.range(of: "Friday passes")
        XCTAssertNotNil(destroyed, said)
        XCTAssertNotNil(handed, said)
        XCTAssertTrue(destroyed!.lowerBound < handed!.lowerBound, said)
    }

    func testAHandoverIsDescribedAsAHandoverAndNotAsALoss() {
        let said = AccountDeletionPlan.consequence(
            for: AccountDeletionPlan.outcome(for: [mine("Friday", members: 3)]))
        XCTAssertTrue(said.contains("passes to the next person invited"), said)
        XCTAssertTrue(said.contains("the band keeps it"), said)
        XCTAssertFalse(said.contains("Friday is deleted"), said)
    }

    func testNothingClaimsToBeDeletedWhenNothingWillBe() {
        let said = AccountDeletionPlan.consequence(
            for: AccountDeletionPlan.outcome(for: [
                mine("Friday", members: 3), theirs("The band's"),
            ]))
        XCTAssertFalse(said.contains("is deleted"), said)
        XCTAssertFalse(said.contains("are deleted"), said)
        XCTAssertTrue(said.contains("carries on without you"), said)
    }

    func testTheMarksAreMentionedWhenThereIsAnySharedSetListAtAll() {
        // Ink is the thing a person would not think to ask about.
        let shared = AccountDeletionPlan.consequence(
            for: AccountDeletionPlan.outcome(for: [theirs("The band's")]))
        XCTAssertTrue(shared.contains("pencil marks"), shared)
        // And not mentioned when there is nowhere for them to be.
        let alone = AccountDeletionPlan.consequence(for: .init(handedOn: [], destroyed: [], left: []))
        XCTAssertFalse(alone.contains("pencil marks"), alone)
        XCTAssertTrue(alone.contains("cannot be undone"), alone)
    }

    func testThePlainStatementThatTheLibraryStaysIsUnconditional() {
        // The promise a local-first app can actually make, and the reason
        // "delete my account" must not read as "delete my library".
        let keeps = AccountDeletionPlan.keepsLocalLibrary
        XCTAssertTrue(keeps.contains("stays on this iPad"), keeps)
        XCTAssertTrue(keeps.contains("does not touch the music"), keeps)
    }

    // MARK: - naming several set lists

    func testOneTwoAndManyAreNamedDifferently() {
        XCTAssertEqual(AccountDeletionPlan.list(["Friday"]), "Friday")
        XCTAssertEqual(AccountDeletionPlan.list(["Friday", "Duo"]), "Friday and Duo")
        XCTAssertEqual(AccountDeletionPlan.list(["Friday", "Duo", "Practice"]),
                       "Friday, Duo and 1 other")
        XCTAssertEqual(AccountDeletionPlan.list(["a", "b", "c", "d", "e"]),
                       "a, b and 3 others")
    }

    func testAnUnnamedSetListStillReadsAsSomething() {
        // Names come off Firestore documents and a blank one is possible.
        // "  is deleted" is not a sentence anybody can act on.
        XCTAssertEqual(AccountDeletionPlan.list([""]), "an unnamed set list")
    }

    func testPluralsAgreeInEveryClause() {
        let two = AccountDeletionPlan.consequence(
            for: AccountDeletionPlan.outcome(for: [
                mine("A", members: 1), mine("B", members: 1),
                mine("C", members: 3), mine("D", members: 3),
                theirs("E"), theirs("F"),
            ]))
        XCTAssertTrue(two.contains("A and B are deleted"), two)
        XCTAssertTrue(two.contains("nobody else is in them"), two)
        XCTAssertTrue(two.contains("C and D pass to the next person invited"), two)
        XCTAssertTrue(two.contains("the band keeps them"), two)
        XCTAssertTrue(two.contains("E and F, which carry on without you"), two)
    }

    func testTheQuestionIsAQuestionAndCarriesNoDetail() {
        // The detail belongs in the consequence, where there is room to be
        // specific. A question that carries both is one nobody finishes.
        XCTAssertEqual(AccountDeletionPlan.question(), "Delete your account?")
    }
}
