// Who inherits a shared set list when its owner leaves for good.
//
// design/FIREBASE.md §6.6, which closed §12.6: *"transfer setlist ownership to
// the NEXT person who was invited to that setlist -- ownership passes down the
// invite order."*
//
// It is a separate module from `index.js` for one reason: `index.js` calls
// `initializeApp()` at load, so importing it outside the emulator is not
// possible, and the ordering rule is the part of account deletion most worth
// testing without a cloud. `succession.test.mjs` imports this file directly.
//
// THE ORDER IS A STORED INTEGER, not a timestamp (§6.6):
//
//   - `invitedAt` is the order people were ASKED, which is the order the
//     answer names -- but invites are deletable and revocable, so the record
//     can vanish while the member remains.
//   - `joinedAt` is the order people ACCEPTED, which is a different order.
//     Somebody invited first and slow to accept would be skipped.
//
// So `claimInvite` stamps `succession` on the membership row from the set
// list's own monotonic counter, inside the transaction that admits the member.
// The owner is 0. It is never reused, even after somebody leaves.

/// The rows that have no `succession` at all.
///
/// Not hypothetical: every membership written before the counter existed --
/// including everything in the project as deployed at build 200 -- has no such
/// field, and those set lists have to have an answer too. They sort AFTER
/// every numbered row, because a number is evidence of invite order and a
/// missing one is not, and among themselves by `joinedAt` and then by uid so
/// that two clients asked the same question get the same name.
const UNNUMBERED = Number.MAX_SAFE_INTEGER;

/// Normalise one membership row into the three fields the ordering reads.
///
/// `joinedAt` arrives as a Firestore Timestamp from the server, as a number
/// from a test, and as `undefined` from a row written before it was set.
function key(row) {
  const succession = Number.isInteger(row.succession) ? row.succession : UNNUMBERED;
  let joined = Number.POSITIVE_INFINITY;
  if (row.joinedAt && typeof row.joinedAt.toMillis === "function") {
    joined = row.joinedAt.toMillis();
  } else if (typeof row.joinedAt === "number" && Number.isFinite(row.joinedAt)) {
    joined = row.joinedAt;
  }
  return { userId: String(row.userId), succession, joined };
}

/// Every candidate heir, best first.
///
/// Exported as well as `pickSuccessor` because a caller that has to skip a
/// member -- one whose membership row has gone missing, say -- needs the next
/// name rather than a second guess at the rule.
function successionOrder(rows) {
  return rows
    .filter((row) => row && row.userId)
    .map(key)
    .sort((a, b) => {
      if (a.succession !== b.succession) return a.succession - b.succession;
      if (a.joined !== b.joined) return a.joined - b.joined;
      // Total, so the answer does not depend on the order the rows were read.
      return a.userId < b.userId ? -1 : a.userId > b.userId ? 1 : 0;
    })
    .map((row) => row.userId);
}

/// The one who inherits, or null when the departing owner is the last member.
///
/// Null is not a failure. §6.6: *"a set list whose owner is its only member
/// ... is deleted with the account, because there is no other person's work in
/// it to protect -- which is the one place where deleting on account deletion
/// is the right answer rather than the lazy one."* The caller decides that;
/// this only reports that there is nobody.
///
/// `ownerId` is excluded here rather than by the caller so that no caller can
/// forget to, and hand a set list to the person who is leaving it.
function pickSuccessor(rows, ownerId) {
  const order = successionOrder(rows.filter((row) => row && row.userId !== ownerId));
  return order.length ? order[0] : null;
}

// CommonJS, because `index.js` is: a Cloud Functions entry point loaded by the
// runtime cannot `require()` an ES module. Node's ESM loader reads these three
// back as named imports, which is what lets `succession.test.mjs` import the
// file directly with no emulator running.
exports.successionOrder = successionOrder;
exports.pickSuccessor = pickSuccessor;
exports.SUCCESSION_UNNUMBERED = UNNUMBERED;
