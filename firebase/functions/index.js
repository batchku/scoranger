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

/// Claim an invitation. The only way to become a member.
exports.claimInvite = onCall({ region: "us-west1" }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");

  const email = request.auth.token.email;
  const verified = request.auth.token.email_verified === true;
  const inviteId = request.data?.inviteId;
  if (!inviteId) throw new HttpsError("invalid-argument", "Which invitation?");
  // An unverified address is not an identity: without this the invite is
  // claimable by anyone who can type the address (§0.4).
  if (!verified || !email) {
    throw new HttpsError("permission-denied", "Confirm your email address first.");
  }

  return db.runTransaction(async (tx) => {
    const inviteRef = db.collection("invites").doc(inviteId);
    const invite = await tx.get(inviteRef);
    if (!invite.exists) throw new HttpsError("not-found", "That invitation is gone.");
    const data = invite.data();

    if (data.revokedAt) throw new HttpsError("permission-denied", "That invitation was withdrawn.");
    if (data.acceptedAt) throw new HttpsError("failed-precondition", "That invitation has already been used.");
    if (data.emailLower !== email.trim().toLowerCase()) {
      throw new HttpsError("permission-denied", "That invitation was sent to a different address.");
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
    tx.update(inviteRef, {
      acceptedAt: FieldValue.serverTimestamp(),
      acceptedBy: uid,
    });
    return { setlistId: data.setlistId, role: "member" };
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
