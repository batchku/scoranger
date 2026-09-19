// The five callable Functions, exercised end to end against the emulators.
//
// The rules tests next door assert what a CLIENT may write. These assert what
// the SERVER does with what it is asked, which is where the sharing feature
// actually lives: membership is server-authoritative (design/FIREBASE.md §4.4)
// and `memberships/` refuses every client write, so promotion, invitation,
// claiming, revocation and removal exist only here.
//
// It is written because three builds shipped with sharing dead and the
// artifacts all looked right. A round trip -- share, invite, claim, and see
// the other person's row appear -- is the only thing that shows the feature
// works, and Ali cannot be the one to discover it does not.
//
// Run: cd firebase && npm run test:functions
import { readFileSync } from 'node:fs';
import { initializeApp, deleteApp } from 'firebase/app';
import {
  getAuth, connectAuthEmulator, createUserWithEmailAndPassword,
  signInWithEmailAndPassword, signOut,
} from 'firebase/auth';
import {
  getFirestore, connectFirestoreEmulator, doc, getDoc, collection,
  query, where, getDocs,
} from 'firebase/firestore';
import {
  getFunctions, connectFunctionsEmulator, httpsCallable,
} from 'firebase/functions';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc as adminDoc, setDoc as adminSetDoc, getDoc as adminGetDoc } from 'firebase/firestore';

const PROJECT = process.env.GCLOUD_PROJECT || 'scoranger-rules-test';
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
const [FS_HOST, FS_PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8181').split(':');
const REGION = 'us-west1';

// A rules-bypassing writer, for the two states no client and no Function can
// produce: an invitation whose deadline is already past, and a setlist that is
// already full. Both are conditions the server must refuse, so both have to be
// reachable from a test.
const priv = await initializeTestEnvironment({
  projectId: PROJECT,
  firestore: { rules: readFileSync('firestore.rules', 'utf8') },
});
async function asAdmin(work) {
  await priv.withSecurityRulesDisabled((ctx) => work(ctx.firestore()));
}

// ---------------------------------------------------------------------------
// people
// ---------------------------------------------------------------------------

let nextUser = 0;
/// A signed-in person with a VERIFIED address, which is what every claim path
/// requires. The auth emulator creates accounts unverified, so the flag is set
/// through its admin endpoint and the ID token is then force-refreshed --
/// email_verified is a claim baked into the token, not read live.
async function person({ verified = true } = {}) {
  nextUser += 1;
  const email = `p${nextUser}-${Date.now()}@example.com`;
  const app = initializeApp({ apiKey: 'fake-api-key', projectId: PROJECT },
    `app-${nextUser}-${Date.now()}`);
  const auth = getAuth(app);
  connectAuthEmulator(auth, `http://${AUTH_HOST}`, { disableWarnings: true });
  const db = getFirestore(app);
  connectFirestoreEmulator(db, FS_HOST, Number(FS_PORT));
  const fns = getFunctions(app, REGION);
  connectFunctionsEmulator(fns, FS_HOST, 5001);

  const cred = await createUserWithEmailAndPassword(auth, email, 'password-12');
  if (verified) {
    const res = await fetch(
      `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:update`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: 'Bearer owner' },
        body: JSON.stringify({ localId: cred.user.uid, emailVerified: true }),
      });
    if (!res.ok) throw new Error(`could not verify ${email}: ${await res.text()}`);
    await cred.user.getIdToken(true);
  }
  return {
    uid: cred.user.uid, email, app, auth, db,
    call: (name, data) => httpsCallable(fns, name)(data).then((r) => r.data),
    signOut: () => signOut(auth),
    signIn: () => signInWithEmailAndPassword(auth, email, 'password-12'),
  };
}

/// Nobody: an app with no signed-in user, for the unauthenticated paths.
function nobody() {
  const app = initializeApp({ apiKey: 'fake-api-key', projectId: PROJECT },
    `anon-${Date.now()}-${Math.random()}`);
  const auth = getAuth(app);
  connectAuthEmulator(auth, `http://${AUTH_HOST}`, { disableWarnings: true });
  const fns = getFunctions(app, REGION);
  connectFunctionsEmulator(fns, FS_HOST, 5001);
  return { call: (name, data) => httpsCallable(fns, name)(data).then((r) => r.data) };
}

// ---------------------------------------------------------------------------
// harness
// ---------------------------------------------------------------------------

let ran = 0; const failures = [];
/// ONLY=<substring> runs one test, for reversal checks -- patch the Function,
/// see the test that covers it go red, put it back.
const ONLY = process.env.ONLY;
async function test(name, body) {
  if (ONLY && !name.includes(ONLY)) return;
  ran += 1;
  try { await body(); console.log(`  ok   ${name}`); }
  catch (e) { failures.push([name, e]); console.log(`  FAIL ${name}\n       ${e && e.message}`); }
}
function eq(actual, expected, what) {
  const a = JSON.stringify(actual); const b = JSON.stringify(expected);
  if (a !== b) throw new Error(`${what}: expected ${b}, got ${a}`);
}
function ok(cond, what) { if (!cond) throw new Error(what); }
/// The call must be refused, with THAT code. A wrong-code refusal is a
/// different bug wearing the right answer's clothes.
async function refused(code, work, what) {
  try { await work(); }
  catch (e) {
    const got = (e.code || '').replace(/^functions\//, '');
    if (got !== code) throw new Error(`${what}: expected ${code}, got ${e.code}: ${e.message}`);
    return e;
  }
  throw new Error(`${what}: expected ${code}, but it succeeded`);
}

const id = (p) => `${p}-${Math.random().toString(36).slice(2, 10)}`;

// ---------------------------------------------------------------------------
// promotion: the fix for both of the screenshots
// ---------------------------------------------------------------------------

console.log('\nshareSetlist');

await test('promotion writes the setlist AND the owner\'s membership row', async () => {
  const ali = await person();
  const set = id('set');
  const r = await ali.call('shareSetlist', { setlistId: set, name: 'Friday' });
  eq(r.role, 'owner', 'role returned');
  eq(r.created, true, 'created');
  eq(r.setlistId, set, 'setlistId');

  // The setlist, read by its owner.
  const s = await getDoc(doc(ali.db, 'setlists', set));
  ok(s.exists(), 'setlist document exists');
  eq(s.data().ownerId, ali.uid, 'ownerId');
  eq(s.data().members[ali.uid], 'owner', 'members map');
  eq(s.data().memberIds, [ali.uid], 'memberIds');

  // THE HALF THAT WAS MISSING. Without this row the app's list of shared set
  // lists is empty and SharedSetlistScreen has no role to show -- which is
  // exactly what Ali photographed.
  const m = await getDoc(doc(ali.db, 'memberships', `${ali.uid}_${set}`));
  ok(m.exists(), 'the owner has a memberships row');
  eq(m.data().role, 'owner', 'membership role');
  eq(m.data().succession, 0, 'the owner is first in the succession order');
});

await test('the owner finds their own set list by the query the app runs', async () => {
  const ali = await person();
  const set = id('set');
  await ali.call('shareSetlist', { setlistId: set, name: 'Friday' });
  // SharedSetlists.swift watches exactly this query.
  const rows = await getDocs(query(collection(ali.db, 'memberships'),
    where('userId', '==', ali.uid)));
  eq(rows.docs.map((d) => d.data().setlistId), [set], 'the query the app runs');
});

await test('sharing twice is the same share', async () => {
  const ali = await person();
  const set = id('set');
  await ali.call('shareSetlist', { setlistId: set, name: 'Friday' });
  const again = await ali.call('shareSetlist', { setlistId: set, name: 'Friday' });
  eq(again.created, false, 'created on the second call');
  eq(again.role, 'owner', 'role on the second call');
});

await test('somebody else\'s set list id is refused, never merged', async () => {
  const ali = await person(); const son = await person();
  const set = id('set');
  await ali.call('shareSetlist', { setlistId: set, name: 'Friday' });
  await refused('already-exists',
    () => son.call('shareSetlist', { setlistId: set, name: 'Mine now' }),
    'a stranger claiming an existing id');
});

await test('signed out, sharing is refused', async () => {
  await refused('unauthenticated',
    () => nobody().call('shareSetlist', { setlistId: id('set'), name: 'x' }),
    'anonymous share');
});

await test('a set list id with a path separator in it is refused', async () => {
  const ali = await person();
  await refused('invalid-argument',
    () => ali.call('shareSetlist', { setlistId: 'a/b', name: 'x' }),
    'path traversal in the id');
});

// ---------------------------------------------------------------------------
// invitation
// ---------------------------------------------------------------------------

console.log('\ncreateInvite');

await test('a link is open by default and expires in seven days', async () => {
  const ali = await person();
  const set = id('set');
  await ali.call('shareSetlist', { setlistId: set, name: 'Friday' });
  const inv = await ali.call('createInvite', { setlistId: set });
  eq(inv.claim, 'open', 'the default claim rule');
  const days = (new Date(inv.expiresAt).getTime() - Date.now()) / 86400000;
  ok(days > 6.9 && days < 7.1, `expiry is seven days out, got ${days}`);
  ok(typeof inv.inviteId === 'string' && inv.inviteId.length > 8, 'invite id');
});

await test('an addressed invitation needs an address', async () => {
  const ali = await person();
  const set = id('set');
  await ali.call('shareSetlist', { setlistId: set, name: 'Friday' });
  await refused('invalid-argument',
    () => ali.call('createInvite', { setlistId: set, claim: 'address' }),
    'addressed invite with no email');
});

await test('a stranger cannot mint a link to a set list they are not in', async () => {
  const ali = await person(); const stranger = await person();
  const set = id('set');
  await ali.call('shareSetlist', { setlistId: set, name: 'Friday' });
  await refused('permission-denied',
    () => stranger.call('createInvite', { setlistId: set }),
    'stranger minting an invite');
});

// ---------------------------------------------------------------------------
// the round trip
// ---------------------------------------------------------------------------

console.log('\nclaimInvite');

/// Share, invite, claim: the whole feature in one function, so every test
/// below starts from a group that actually exists.
async function group({ named = 'Friday' } = {}) {
  const owner = await person();
  const setlistId = id('set');
  await owner.call('shareSetlist', { setlistId, name: named });
  const inv = await owner.call('createInvite', { setlistId });
  return { owner, setlistId, inviteId: inv.inviteId };
}

await test('a second person claims the link and lands in the set list', async () => {
  const { owner, setlistId, inviteId } = await group();
  const son = await person();
  const r = await son.call('claimInvite', { inviteId });
  eq(r.role, 'member', 'the role a claimer gets');
  eq(r.setlistId, setlistId, 'the set list claimed');

  // Both halves, from the joiner's side.
  const m = await getDoc(doc(son.db, 'memberships', `${son.uid}_${setlistId}`));
  ok(m.exists(), 'the joiner has a memberships row');
  eq(m.data().role, 'member', 'the joiner\'s role');
  const s = await getDoc(doc(son.db, 'setlists', setlistId));
  ok(s.exists(), 'the joiner can read the set list');
  eq(s.data().members[owner.uid], 'owner', 'the owner is still the owner');
  eq(s.data().members[son.uid], 'member', 'the joiner is in the members map');
  ok(s.data().memberIds.includes(son.uid), 'the joiner is in memberIds');

  // And from the owner's: the group now has two people in it.
  const fromOwner = await getDoc(doc(owner.db, 'setlists', setlistId));
  eq(Object.keys(fromOwner.data().members).length, 2, 'members, seen by the owner');
});

await test('claiming twice is idempotent', async () => {
  const { inviteId } = await group();
  const son = await person();
  await son.call('claimInvite', { inviteId });
  const again = await son.call('claimInvite', { inviteId });
  eq(again.role, 'member', 'role on the second claim');
});

await test('one open link brings in several people, and counts them', async () => {
  const { setlistId, inviteId, owner } = await group();
  const a = await person(); const b = await person();
  await a.call('claimInvite', { inviteId });
  await b.call('claimInvite', { inviteId });
  const s = await getDoc(doc(owner.db, 'setlists', setlistId));
  eq(Object.keys(s.data().members).length, 3, 'members after two claims');
  await asAdmin(async (db) => {
    const inv = await adminGetDoc(adminDoc(db, 'invites', inviteId));
    eq(inv.data().claimCount, 2, 'claimCount');
  });
});

await test('an unverified address cannot claim', async () => {
  const { inviteId } = await group();
  const stranger = await person({ verified: false });
  await refused('permission-denied',
    () => stranger.call('claimInvite', { inviteId }),
    'unverified claimer');
});

await test('signed out, claiming is refused', async () => {
  const { inviteId } = await group();
  await refused('unauthenticated',
    () => nobody().call('claimInvite', { inviteId }),
    'anonymous claim');
});

await test('an invitation that does not exist is refused', async () => {
  const son = await person();
  await refused('not-found',
    () => son.call('claimInvite', { inviteId: 'no-such-invite' }),
    'bogus invite id');
});

await test('an addressed invitation is claimable only by its address', async () => {
  const owner = await person();
  const setlistId = id('set');
  await owner.call('shareSetlist', { setlistId, name: 'Friday' });
  const son = await person(); const other = await person();
  const inv = await owner.call('createInvite',
    { setlistId, claim: 'address', email: son.email });
  await refused('permission-denied',
    () => other.call('claimInvite', { inviteId: inv.inviteId }),
    'the wrong address claiming an addressed invite');
  const r = await son.call('claimInvite', { inviteId: inv.inviteId });
  eq(r.role, 'member', 'the right address claiming');
});

await test('an addressed invitation is single use', async () => {
  const owner = await person();
  const setlistId = id('set');
  await owner.call('shareSetlist', { setlistId, name: 'Friday' });
  const son = await person(); const third = await person();
  const inv = await owner.call('createInvite',
    { setlistId, claim: 'address', email: son.email });
  await son.call('claimInvite', { inviteId: inv.inviteId });
  // Used. A different person cannot ride the same document, whatever address
  // it names -- addressed invites fail closed.
  await refused('failed-precondition',
    () => third.call('claimInvite', { inviteId: inv.inviteId }),
    'a used addressed invite');
});

await test('an unrecognised claim rule fails CLOSED, to addressed', async () => {
  const { setlistId, inviteId } = await group();
  const son = await person();
  // A document minted by some future or hostile client, carrying a rule this
  // function does not know. §8.2 guard rail 1 rests on this being refused.
  await asAdmin((db) => adminSetDoc(adminDoc(db, 'invites', inviteId), {
    setlistId, setlistName: 'Friday', claim: 'everybody-welcome',
    emailLower: null, expiresAt: new Date(Date.now() + 86400000),
    revokedAt: null, claimCount: 0, invitedBy: 'x', invitedAt: new Date(),
  }));
  await refused('permission-denied',
    () => son.call('claimInvite', { inviteId }),
    'an invite with an unknown claim rule');
});

await test('an expired link is refused against the SERVER clock', async () => {
  const { setlistId, inviteId } = await group();
  const son = await person();
  await asAdmin((db) => adminSetDoc(adminDoc(db, 'invites', inviteId), {
    setlistId, setlistName: 'Friday', claim: 'open', emailLower: null,
    expiresAt: new Date(Date.now() - 60000),
    revokedAt: null, claimCount: 0, invitedBy: 'x', invitedAt: new Date(),
  }));
  await refused('deadline-exceeded',
    () => son.call('claimInvite', { inviteId }),
    'an expired invite');
});

await test('twelve is the cap, and the thirteenth is refused', async () => {
  const { owner, setlistId, inviteId } = await group();
  // Eleven strangers beside the owner: a full group, written straight in
  // because eleven round trips through the emulator is a minute of nothing.
  const members = { [owner.uid]: 'owner' };
  const ids = [owner.uid];
  for (let i = 0; i < 11; i += 1) { members[`filler-${i}`] = 'member'; ids.push(`filler-${i}`); }
  await asAdmin((db) => adminSetDoc(adminDoc(db, 'setlists', setlistId), {
    name: 'Friday', ownerId: owner.uid, members, memberIds: ids,
  }));
  const thirteenth = await person();
  await refused('resource-exhausted',
    () => thirteenth.call('claimInvite', { inviteId }),
    'the thirteenth person');

  // And eleven is not full: take one out and the door opens again.
  delete members['filler-10']; ids.pop();
  await asAdmin((db) => adminSetDoc(adminDoc(db, 'setlists', setlistId), {
    name: 'Friday', ownerId: owner.uid, members, memberIds: ids,
  }));
  const r = await thirteenth.call('claimInvite', { inviteId });
  eq(r.role, 'member', 'the twelfth person');
});

// ---------------------------------------------------------------------------
// revocation
// ---------------------------------------------------------------------------

console.log('\nrevokeInvite');

await test('the owner revokes, and the link stops working', async () => {
  const { owner, inviteId } = await group();
  const early = await person(); const late = await person();
  await early.call('claimInvite', { inviteId });
  eq((await owner.call('revokeInvite', { inviteId })).revoked, true, 'revoked');
  await refused('permission-denied',
    () => late.call('claimInvite', { inviteId }),
    'claiming a revoked link');
});

await test('revoking closes the door; it does not remove anybody', async () => {
  const { owner, setlistId, inviteId } = await group();
  const son = await person();
  await son.call('claimInvite', { inviteId });
  await owner.call('revokeInvite', { inviteId });
  const s = await getDoc(doc(son.db, 'setlists', setlistId));
  eq(s.data().members[son.uid], 'member', 'a member who joined before the revoke');
});

await test('revoking keeps the record of who used the link', async () => {
  const { owner, inviteId } = await group();
  const son = await person();
  await son.call('claimInvite', { inviteId });
  await owner.call('revokeInvite', { inviteId });
  await asAdmin(async (db) => {
    const inv = await adminGetDoc(adminDoc(db, 'invites', inviteId));
    ok(inv.exists(), 'the invitation document survives revocation');
    eq(inv.data().acceptedBy, son.uid, 'who claimed it');
    ok(inv.data().revokedAt != null, 'revokedAt is stamped');
  });
});

await test('a member may invite but may not revoke', async () => {
  const { owner, setlistId, inviteId } = await group();
  const son = await person();
  await son.call('claimInvite', { inviteId });
  // A member CAN mint a link (createInvite allows owner or member).
  const theirs = await son.call('createInvite', { setlistId });
  ok(theirs.inviteId, 'a member can mint a link');
  await refused('permission-denied',
    () => son.call('revokeInvite', { inviteId: theirs.inviteId }),
    'a member revoking');
});

// ---------------------------------------------------------------------------
// removal
// ---------------------------------------------------------------------------

console.log('\nremoveMember');

await test('the owner removes somebody, and their row goes with them', async () => {
  const { owner, setlistId, inviteId } = await group();
  const son = await person();
  await son.call('claimInvite', { inviteId });
  eq((await owner.call('removeMember', { setlistId, userId: son.uid })).removed,
    true, 'removed');
  const s = await getDoc(doc(owner.db, 'setlists', setlistId));
  ok(!(son.uid in s.data().members), 'gone from the members map');
  ok(!s.data().memberIds.includes(son.uid), 'gone from memberIds');
  await asAdmin(async (db) => {
    const m = await adminGetDoc(adminDoc(db, 'memberships', `${son.uid}_${setlistId}`));
    ok(!m.exists(), 'their memberships row is gone');
  });
});

await test('anybody may leave', async () => {
  const { setlistId, inviteId } = await group();
  const son = await person();
  await son.call('claimInvite', { inviteId });
  eq((await son.call('removeMember', { setlistId, userId: son.uid })).removed,
    true, 'leaving');
});

await test('a member cannot remove another member', async () => {
  const { setlistId, inviteId } = await group();
  const a = await person(); const b = await person();
  await a.call('claimInvite', { inviteId });
  await b.call('claimInvite', { inviteId });
  await refused('permission-denied',
    () => a.call('removeMember', { setlistId, userId: b.uid }),
    'a member removing a peer');
});

await test('the owner cannot leave their own set list', async () => {
  const { owner, setlistId } = await group();
  await refused('failed-precondition',
    () => owner.call('removeMember', { setlistId, userId: owner.uid }),
    'the owner leaving');
});

// ---------------------------------------------------------------------------
// succession, and deleting an account
// ---------------------------------------------------------------------------

console.log('\ndeleteAccount');

await test('a claiming member is stamped with the next succession number', async () => {
  const { owner, setlistId, inviteId } = await group();
  const first = await person(); const second = await person();
  await first.call('claimInvite', { inviteId });
  await second.call('claimInvite', { inviteId });
  await asAdmin(async (db) => {
    const a = await adminGetDoc(adminDoc(db, 'memberships', `${first.uid}_${setlistId}`));
    const b = await adminGetDoc(adminDoc(db, 'memberships', `${second.uid}_${setlistId}`));
    eq(a.data().succession, 1, 'the first to claim');
    eq(b.data().succession, 2, 'the second to claim');
    const s = await adminGetDoc(adminDoc(db, 'setlists', setlistId));
    eq(s.data().nextSuccession, 3, 'the counter moved twice');
  });
  ok(owner, 'owner exists');
});

await test('a number is not reused after the member who had it leaves', async () => {
  // §6.6 in one assertion: the gap stays a gap, so the order of everybody
  // still in the set list is the order they were asked, permanently.
  const { owner, setlistId, inviteId } = await group();
  const first = await person();
  await first.call('claimInvite', { inviteId });
  await owner.call('removeMember', { setlistId, userId: first.uid });
  const second = await person();
  await second.call('claimInvite', { inviteId });
  await asAdmin(async (db) => {
    const b = await adminGetDoc(adminDoc(db, 'memberships', `${second.uid}_${setlistId}`));
    eq(b.data().succession, 2, 'the number after the one that left');
  });
});

await test('the owner leaving hands the set list on, by the stored order', async () => {
  const { owner, setlistId, inviteId } = await group();
  const second = await person(); const third = await person();
  await second.call('claimInvite', { inviteId });
  await third.call('claimInvite', { inviteId });

  // THE INVITATION IS DESTROYED before the handover. This is what the stored
  // integer buys over reading `invitedAt` off the invite (§6.6): invites are
  // deletable and revocable, so the record can vanish while the member
  // remains, and the order has to survive that.
  await asAdmin(async (db) => {
    await adminSetDoc(adminDoc(db, 'invites', inviteId), { setlistId, gone: true });
  });
  await owner.call('removeMember', { setlistId, userId: second.uid });
  await second.call('claimInvite', { inviteId }).catch(() => {});
  // Put `second` back by hand with their ORIGINAL number, which is what a
  // real rejoin would not do -- the point is that 1 still beats 2.
  await asAdmin(async (db) => {
    await adminSetDoc(adminDoc(db, 'memberships', `${second.uid}_${setlistId}`), {
      userId: second.uid, setlistId, role: 'member', succession: 1,
      joinedAt: new Date(Date.now() + 60000),
    });
    const s = await adminGetDoc(adminDoc(db, 'setlists', setlistId));
    await adminSetDoc(adminDoc(db, 'setlists', setlistId), {
      members: { ...s.data().members, [second.uid]: 'member' },
      memberIds: [...new Set([...s.data().memberIds, second.uid])],
    }, { merge: true });
  });

  const result = await owner.call('deleteAccount', {});
  // `second` joined LAST by the clock and is still the heir, because 1 < 2.
  eq(result.handedOver, [{ setlistId, heir: second.uid }], 'who it went to');
  eq(result.emptied, [], 'nothing was destroyed');

  await asAdmin(async (db) => {
    const s = await adminGetDoc(adminDoc(db, 'setlists', setlistId));
    ok(s.exists(), 'the set list survives its owner');
    eq(s.data().ownerId, second.uid, 'the new ownerId');
    eq(s.data().members[second.uid], 'owner', 'the new owner in the map');
    ok(!(owner.uid in s.data().members), 'the departing owner is out of the map');
    ok(!s.data().memberIds.includes(owner.uid), 'and out of memberIds');
    // The flat index has to agree, or the heir opens it as a reader.
    const m = await adminGetDoc(adminDoc(db, 'memberships', `${second.uid}_${setlistId}`));
    eq(m.data().role, 'owner', "the heir's own row");
    const gone = await adminGetDoc(adminDoc(db, 'memberships', `${owner.uid}_${setlistId}`));
    ok(!gone.exists(), 'the departing owner has no row left');
    ok(third.uid in s.data().members, 'and the third member is still in it');
  });
});

await test('a set list whose owner is its only member is deleted with the account',
  async () => {
    const { owner, setlistId } = await group();
    const result = await owner.call('deleteAccount', {});
    eq(result.emptied, [setlistId], 'emptied');
    eq(result.handedOver, [], 'nothing to hand on');
    await asAdmin(async (db) => {
      const s = await adminGetDoc(adminDoc(db, 'setlists', setlistId));
      ok(!s.exists(), 'the set list is gone');
      const m = await adminGetDoc(adminDoc(db, 'memberships', `${owner.uid}_${setlistId}`));
      ok(!m.exists(), 'and so is the membership row');
    });
  });

await test('a member deleting their account leaves the set list standing', async () => {
  const { owner, setlistId, inviteId } = await group();
  const son = await person();
  await son.call('claimInvite', { inviteId });
  const result = await son.call('deleteAccount', {});
  eq(result.left, [setlistId], 'left');
  eq(result.handedOver, [], 'they owned nothing');
  eq(result.emptied, [], 'nothing destroyed');
  await asAdmin(async (db) => {
    const s = await adminGetDoc(adminDoc(db, 'setlists', setlistId));
    ok(s.exists(), 'somebody else\'s set list is untouched');
    eq(s.data().ownerId, owner.uid, 'still theirs');
    ok(!(son.uid in s.data().members), 'the member is out');
    ok(!s.data().memberIds.includes(son.uid), 'and out of memberIds');
  });
});

await test('their own ink goes, and nobody else\'s does', async () => {
  const { owner, setlistId, inviteId } = await group();
  const son = await person();
  await son.call('claimInvite', { inviteId });
  await asAdmin(async (db) => {
    await adminSetDoc(adminDoc(db, 'setlists', setlistId, 'entries', 'e1'), { title: 'Tune' });
    await adminSetDoc(adminDoc(db, 'setlists', setlistId, 'entries', 'e1', 'ink', son.uid),
      { strokes: 'theirs' });
    await adminSetDoc(adminDoc(db, 'setlists', setlistId, 'entries', 'e1', 'ink', owner.uid),
      { strokes: 'the owner\'s' });
  });
  await son.call('deleteAccount', {});
  await asAdmin(async (db) => {
    const theirs = await adminGetDoc(
      adminDoc(db, 'setlists', setlistId, 'entries', 'e1', 'ink', son.uid));
    ok(!theirs.exists(), 'the departing member\'s ink is gone');
    const others = await adminGetDoc(
      adminDoc(db, 'setlists', setlistId, 'entries', 'e1', 'ink', owner.uid));
    ok(others.exists(), 'THE OWNER\'S INK IS NOT TOUCHED');
  });
});

await test('an invitation they minted into a surviving set list is revoked, not deleted',
  async () => {
    const { owner, setlistId, inviteId } = await group();
    const son = await person();
    await son.call('claimInvite', { inviteId });
    const theirs = await son.call('createInvite', { setlistId });
    eq((await son.call('deleteAccount', {})).revokedInvites, 1, 'revoked');
    await asAdmin(async (db) => {
      const inv = await adminGetDoc(adminDoc(db, 'invites', theirs.inviteId));
      ok(inv.exists(), 'the record of the invitation survives');
      ok(inv.data().revokedAt, 'and it is closed');
    });
    // The closed link admits nobody, which is what revocation has to mean.
    const stranger = await person();
    await refused('permission-denied',
      () => stranger.call('claimInvite', { inviteId: theirs.inviteId }),
      'claiming a dead account\'s link');
    ok(owner, 'owner exists');
  });

await test('the Auth user itself is gone', async () => {
  const ali = await person();
  await ali.call('deleteAccount', {});
  const res = await fetch(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:lookup`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer owner' },
      body: JSON.stringify({ localId: [ali.uid] }),
    });
  const body = await res.json();
  ok(!body.users || body.users.length === 0, 'no Auth user with that uid');
});

await test('deleting an account is not something a stranger can do for you', async () => {
  await refused('unauthenticated', () => nobody().call('deleteAccount', {}),
    'an unauthenticated deletion');
});

await test('two set lists, two different fates, in one deletion', async () => {
  // The case the UI has to describe before the button is pressed: some of
  // their set lists are handed on and some are destroyed, and the confirm
  // copy is wrong unless both numbers come back.
  const ali = await person();
  const alone = id('set'); const shared = id('set');
  await ali.call('shareSetlist', { setlistId: alone, name: 'Practice' });
  await ali.call('shareSetlist', { setlistId: shared, name: 'Friday' });
  const inv = await ali.call('createInvite', { setlistId: shared });
  const son = await person();
  await son.call('claimInvite', { inviteId: inv.inviteId });

  const result = await ali.call('deleteAccount', {});
  eq(result.emptied, [alone], 'the one nobody else was in');
  eq(result.handedOver, [{ setlistId: shared, heir: son.uid }], 'the one they were');
  eq(result.incomplete, [], 'nothing left behind');
});

// ---------------------------------------------------------------------------

await priv.cleanup();
console.log(`\n${ran - failures.length}/${ran} passed`);
if (failures.length) {
  console.log('\nfailures:');
  for (const [name, e] of failures) console.log(`  ${name}\n    ${e && e.stack}`);
  process.exit(1);
}
process.exit(0);
