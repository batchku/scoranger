// Membership, which is the one thing a client may not write.
//
// design/FIREBASE.md §4.4 names the server as authoritative for who is in a
// shared setlist, and §12.11 chose a callable Function over security rules for
// claiming an invite: a rule permitting a client to write itself into a
// membership map is the highest-consequence rule in the system to get subtly
// wrong. The deployed rules refuse that write outright, so this is the only
// path in.
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

// §8.2 guard rail 2, and the one enforcement point that can count members
// transactionally -- the rules refuse every client write to the membership map,
// so this Function is the only way in.
//
// TWELVE, meaning twelve people in a group INCLUDING the owner. The owner
// states the limit as an inequality -- "groups of UNDER 12 people", "the
// <12-member cap" -- and has confirmed that max 12 including the owner is the
// intent. This value is what the DEPLOYED function enforces and it has not
// changed; keep SetlistPermission.membershipCap in step with it, and note that
// this is the copy that binds. The client's constant is advisory.
const MEMBERSHIP_CAP = 12;

/// Share a set list: promote a LOCAL set list into a shared one, in place.
///
/// **This exists because the client could not do it.** Creating the setlist
/// document was a client write and writing the `memberships` index is
/// server-only -- the rules say `allow write: if false` on that collection,
/// because membership is server-authoritative (§4.4). So the two halves could
/// never both happen, and the owner of a set list they had just made had no
/// membership row. Two bugs followed from that one gap, both of which Ali
/// photographed:
///
///   - "SHARED WITH THE BAND: Nothing shared yet", because the app lists set
///     lists by querying `memberships` and there was nothing to find;
///   - the creator seeing ONLY a red "Leave this set list", because the screen
///     derived its role from that same empty list and fell back to `reader`.
///
/// The document takes the set list's OWN uid, which is what makes this a
/// promotion rather than a copy: same identity, same row in the one list, no
/// second object to keep in step.
///
/// Idempotent. Sharing an already-shared set list returns it rather than
/// failing, because the share button is going to be pressed twice.
exports.shareSetlist = onCall({ region: "us-west1" }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const { setlistId, name } = request.data || {};
  if (!setlistId) throw new HttpsError("invalid-argument", "Which set list?");
  if (typeof setlistId !== "string" || setlistId.includes("/")) {
    throw new HttpsError("invalid-argument", "That is not a set list id.");
  }

  const setlistRef = db.collection("setlists").doc(setlistId);
  return db.runTransaction(async (tx) => {
    const existing = await tx.get(setlistRef);

    if (existing.exists) {
      const data = existing.data();
      const role = (data.members || {})[uid];
      if (!role) {
        // Somebody else's set list already occupies this id. A uid collision
        // is not supposed to be possible, so this is refused rather than
        // merged -- merging would hand them somebody else's music.
        throw new HttpsError("already-exists",
          "That set list is already shared by somebody else.");
      }
      // Already shared, by this person. Hand it back.
      return { setlistId, role, created: false };
    }

    tx.set(setlistRef, {
      name: typeof name === "string" && name ? name : "Set list",
      ownerId: uid,
      members: { [uid]: "owner" },
      memberIds: [uid],
      createdAt: FieldValue.serverTimestamp(),
    });
    // THE HALF THAT WAS MISSING. Written in the SAME transaction as the
    // setlist, so the owner can never exist without their index row -- which
    // is the state both of Ali's screenshots were showing.
    tx.set(db.collection("memberships").doc(`${uid}_${setlistId}`), {
      userId: uid,
      setlistId,
      setlistName: typeof name === "string" ? name : "",
      role: "owner",
      // The owner is first in the invite order, which is what §6.6's
      // succession reads when an owner deletes their account.
      succession: 0,
      joinedAt: FieldValue.serverTimestamp(),
    });
    return { setlistId, role: "owner", created: true };
  });
});

/// Mint an invitation to a shared set list.
///
/// Server-side so the CLAIM RULE is recorded on the invitation itself rather
/// than assumed by whichever client wrote it. `claim` is either:
///
///   - "address": only the verified email it names may claim it. This is
///     §8.2 guard rail 1 -- an invitation is to an account, never a link --
///     and it is what makes "no public link sharing" true.
///   - "open": anybody holding the link may claim it, up to the cap.
///
/// Both are implemented; which one the app mints is a product decision that is
/// still open, and writing it as DATA means changing the answer later does not
/// need a redeploy or a migration.
exports.createInvite = onCall({ region: "us-west1" }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const { setlistId, email, claim } = request.data || {};
  if (!setlistId) throw new HttpsError("invalid-argument", "Which set list?");
  // (b) is confirmed (§6A.0.1), so an "open" link is the DEFAULT and an
  // addressed one is the explicit exception -- the reverse of before. A caller
  // that says nothing gets the flow Ali asked for.
  const rule = claim === "address" ? "address" : "open";
  if (rule === "address" && !email) {
    throw new HttpsError("invalid-argument",
      "An addressed invitation needs the address it is for.");
  }

  const setlist = await db.collection("setlists").doc(setlistId).get();
  if (!setlist.exists) throw new HttpsError("not-found", "That set list is gone.");
  const role = (setlist.data().members || {})[uid];
  if (role !== "owner" && role !== "member") {
    throw new HttpsError("permission-denied", "You are not in that set list.");
  }

  // SEVEN DAYS. One of the four bounds that replace "never to a link": a
  // forwarded link stops working, so the exposure has an end even if nobody
  // remembers to revoke it. Computed here rather than in the client, because a
  // device clock is not a deadline anybody should be able to move.
  const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
  const expires = new Date(Date.now() + WEEK_MS);

  const invite = db.collection("invites").doc();
  await invite.set({
    setlistId,
    setlistName: setlist.data().name || "",
    emailLower: rule === "address" ? String(email).trim().toLowerCase() : null,
    claim: rule,
    expiresAt: expires,
    revokedAt: null,
    claimCount: 0,
    invitedBy: uid,
    invitedAt: FieldValue.serverTimestamp(),
  });
  return { inviteId: invite.id, claim: rule, expiresAt: expires.toISOString() };
});

/// Claim an invitation. The only way to become a member.
exports.claimInvite = onCall({ region: "us-west1" }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");

  const email = request.auth.token.email;
  const verified = request.auth.token.email_verified === true;
  const inviteId = request.data?.inviteId;
  if (!inviteId) throw new HttpsError("invalid-argument", "Which invitation?");

  return db.runTransaction(async (tx) => {
    const inviteRef = db.collection("invites").doc(inviteId);
    const invite = await tx.get(inviteRef);
    if (!invite.exists) throw new HttpsError("not-found", "That invitation is gone.");
    const data = invite.data();

    if (data.revokedAt) throw new HttpsError("permission-denied", "That invitation was withdrawn.");

    // EXPIRY, checked against the SERVER's clock. An expired link is refused
    // whatever the device believes the time is.
    if (data.expiresAt) {
      const deadline = data.expiresAt.toMillis
        ? data.expiresAt.toMillis()
        : new Date(data.expiresAt).getTime();
      if (Number.isFinite(deadline) && Date.now() > deadline) {
        throw new HttpsError("deadline-exceeded",
          "That invitation has expired. Ask for a new link.");
      }
    }
    if (data.acceptedAt && data.claim !== "open") {
      throw new HttpsError("failed-precondition", "That invitation has already been used.");
    }

    // WHICHEVER RULE THE INVITATION CARRIES. Recorded on the document by
    // `createInvite` rather than decided here, so the product answer can
    // change without a redeploy -- and so an invitation minted under one rule
    // is always claimed under that rule, never re-interpreted by a later
    // version of this function.
    //
    // Anything that is not literally "open" is treated as addressed. A missing
    // or unrecognised value must fail CLOSED: the addressed rule is the one
    // that keeps "an invitation is to an account, never a link" true (§8.2
    // guard rail 1), and it is what the copyright posture rests on.
    if (data.claim === "open") {
      // An open link still requires a verified account -- it is open about
      // WHO may claim it, not about whether they are anybody at all.
      if (!verified || !email) {
        throw new HttpsError("permission-denied",
          "Confirm your email address first.");
      }
    } else {
      // An unverified address is not an identity: without this the invite is
      // claimable by anyone who can type the address (§0.4).
      if (!verified || !email) {
        throw new HttpsError("permission-denied",
          "Confirm your email address first.");
      }
      if (!data.emailLower
          || data.emailLower !== email.trim().toLowerCase()) {
        throw new HttpsError("permission-denied",
          "That invitation was sent to a different address.");
      }
    }

    const setlistRef = db.collection("setlists").doc(data.setlistId);
    const setlist = await tx.get(setlistRef);
    if (!setlist.exists) throw new HttpsError("not-found", "That setlist is gone.");
    const members = setlist.data().members || {};

    // Already in: idempotent rather than an error, so a retried call after a
    // dropped response does not read as a failure to the person tapping.
    if (members[uid]) return { setlistId: data.setlistId, role: members[uid] };

    // Counted inside the transaction, so two people claiming the twelfth and
    // thirteenth places at once cannot both win.
    if (Object.keys(members).length >= MEMBERSHIP_CAP) {
      throw new HttpsError("resource-exhausted", "That setlist is full.");
    }

    tx.update(setlistRef, {
      [`members.${uid}`]: "member",
      memberIds: FieldValue.arrayUnion(uid),
    });
    // The flat index, so "what setlists am I in" is one query the rules can
    // approve on its face -- rules are not filters (§10.1).
    tx.set(db.collection("memberships").doc(`${uid}_${data.setlistId}`), {
      userId: uid,
      setlistId: data.setlistId,
      setlistName: setlist.data().name || "",
      role: "member",
      joinedAt: FieldValue.serverTimestamp(),
    });
    if (data.claim === "open") {
      // Reusable by design, so the stamp records the LATEST claim and a count
      // rather than closing the invitation.
      tx.update(inviteRef, {
        acceptedAt: FieldValue.serverTimestamp(),
        acceptedBy: uid,
        claimCount: FieldValue.increment(1),
      });
    } else {
      tx.update(inviteRef, {
        acceptedAt: FieldValue.serverTimestamp(),
        acceptedBy: uid,
      });
    }
    return { setlistId: data.setlistId, role: "member" };
  });
});

/// Revoke a link, without destroying the record of who used it.
///
/// The third of the four bounds. `invites` refuses every client update
/// (`allow update: if false`), so this is the only path -- and it SETS a field
/// rather than deleting the document, because the owner needs to keep seeing
/// that the link existed and who claimed it. Deleting would take the evidence
/// with it.
///
/// Anybody who has already joined STAYS joined. Revoking closes the door; it
/// is not a way to remove people, which is `removeMember`.
exports.revokeInvite = onCall({ region: "us-west1" }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const { inviteId } = request.data || {};
  if (!inviteId) throw new HttpsError("invalid-argument", "Which invitation?");

  return db.runTransaction(async (tx) => {
    const ref = db.collection("invites").doc(inviteId);
    const invite = await tx.get(ref);
    if (!invite.exists) throw new HttpsError("not-found", "That invitation is gone.");
    const setlist = await tx.get(
      db.collection("setlists").doc(invite.data().setlistId));
    if (!setlist.exists) throw new HttpsError("not-found", "That set list is gone.");
    // The owner's alone: a member may invite, but closing the door on the
    // whole group is not a member's decision.
    if (setlist.data().ownerId !== uid) {
      throw new HttpsError("permission-denied",
        "Only the person who made this set list can revoke its link.");
    }
    tx.update(ref, { revokedAt: FieldValue.serverTimestamp(), revokedBy: uid });
    return { revoked: true };
  });
});

/// Remove somebody. The owner's alone (§0.5), except that anybody may leave.
exports.removeMember = onCall({ region: "us-west1" }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const { setlistId, userId } = request.data || {};
  if (!setlistId || !userId) throw new HttpsError("invalid-argument", "Who, from where?");

  return db.runTransaction(async (tx) => {
    const setlistRef = db.collection("setlists").doc(setlistId);
    const setlist = await tx.get(setlistRef);
    if (!setlist.exists) throw new HttpsError("not-found", "That setlist is gone.");
    const { ownerId, members = {} } = setlist.data();

    const leaving = uid === userId;
    if (!leaving && ownerId !== uid) {
      throw new HttpsError("permission-denied",
        "Only the person who made this setlist can remove somebody else.");
    }
    // The owner may not leave: a setlist with no owner has nobody who can
    // delete it (§12.6, still open).
    if (leaving && ownerId === uid) {
      throw new HttpsError("failed-precondition",
        "You made this setlist. Delete it, or hand it on first.");
    }
    if (!members[userId]) return { removed: false };

    tx.update(setlistRef, {
      [`members.${userId}`]: FieldValue.delete(),
      memberIds: FieldValue.arrayRemove(userId),
    });
    tx.delete(db.collection("memberships").doc(`${userId}_${setlistId}`));
    // Their ink is NOT deleted. Removing somebody ends their access; it does
    // not destroy work, and re-adding them should bring their marks back.
    return { removed: true };
  });
});
