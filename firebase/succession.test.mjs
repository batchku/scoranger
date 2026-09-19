// The ownership handover rule, on its own, with no cloud.
//
// design/FIREBASE.md §6.6. This is the highest-consequence arithmetic in
// account deletion: get it wrong and a band's set list goes to the wrong
// person, or -- worse -- back to the account that is being deleted.
//
// It runs in a second with no emulator because `functions/succession.js`
// imports nothing. The end-to-end half, where the numbers are actually
// allocated by `claimInvite` and read by `deleteAccount`, is in
// `functions.test.mjs`.
//
// Run: cd firebase && npm run test:succession
import { pickSuccessor, successionOrder } from './functions/succession.js';

let ran = 0; const failures = [];
function test(name, body) {
  ran += 1;
  try { body(); console.log(`  ok   ${name}`); }
  catch (e) { failures.push([name, e]); console.log(`  FAIL ${name}\n       ${e && e.message}`); }
}
function eq(actual, expected, what) {
  const a = JSON.stringify(actual); const b = JSON.stringify(expected);
  if (a !== b) throw new Error(`${what}: expected ${b}, got ${a}`);
}

console.log('\nsuccession');

test('the next-invited inherits, not the next to join', () => {
  // The distinction §6.6 exists for: asked second, accepted last.
  const rows = [
    { userId: 'owner', succession: 0, joinedAt: 100 },
    { userId: 'asked-second', succession: 1, joinedAt: 9000 },
    { userId: 'asked-third', succession: 2, joinedAt: 200 },
  ];
  eq(pickSuccessor(rows, 'owner'), 'asked-second', 'the heir');
});

test('the departing owner is never their own heir', () => {
  const rows = [
    { userId: 'owner', succession: 0, joinedAt: 1 },
    { userId: 'sibling', succession: 4, joinedAt: 2 },
  ];
  eq(pickSuccessor(rows, 'owner'), 'sibling', 'the heir');
});

test('a set list whose owner is its only member has no heir', () => {
  eq(pickSuccessor([{ userId: 'owner', succession: 0 }], 'owner'), null, 'the heir');
  eq(pickSuccessor([], 'owner'), null, 'the heir of nothing');
});

test('a gap where somebody left does not change who is next', () => {
  // Numbers are never reused (§6.6), so 1 and 3 with no 2 is the ordinary
  // state of a set list somebody has left, not a fault to repair.
  const rows = [
    { userId: 'owner', succession: 0 },
    { userId: 'third', succession: 3 },
    { userId: 'first', succession: 1 },
  ];
  eq(successionOrder(rows), ['owner', 'first', 'third'], 'the order');
  eq(pickSuccessor(rows, 'owner'), 'first', 'the heir');
});

test('the second handover goes to the next one down', () => {
  const rows = [
    { userId: 'a', succession: 0 },
    { userId: 'b', succession: 1 },
    { userId: 'c', succession: 2 },
  ];
  const first = pickSuccessor(rows, 'a');
  eq(first, 'b', 'the first heir');
  // `b` is now the owner and deletes their account too.
  eq(pickSuccessor(rows.filter((r) => r.userId !== 'a'), first), 'c', 'the second heir');
});

test('a row with no succession number sorts after every row that has one', () => {
  // Every membership written before the counter existed, which is everything
  // deployed at build 200. They must have an answer, and it must not be an
  // answer that beats a numbered row.
  const rows = [
    { userId: 'owner', succession: 0 },
    { userId: 'legacy', joinedAt: 5 },
    { userId: 'numbered', succession: 9, joinedAt: 5000 },
  ];
  eq(successionOrder(rows), ['owner', 'numbered', 'legacy'], 'the order');
  eq(pickSuccessor(rows, 'owner'), 'numbered', 'the heir');
});

test('unnumbered rows fall back to join order, then to uid', () => {
  eq(successionOrder([
    { userId: 'later', joinedAt: 20 },
    { userId: 'earlier', joinedAt: 10 },
  ]), ['earlier', 'later'], 'by joinedAt');
  // No number and no timestamp: still a total order, so two callers reading
  // the same rows in different orders name the same person.
  eq(successionOrder([{ userId: 'zoe' }, { userId: 'ali' }]), ['ali', 'zoe'], 'by uid');
  eq(successionOrder([{ userId: 'ali' }, { userId: 'zoe' }]), ['ali', 'zoe'], 'and the other way round');
});

test('a Firestore Timestamp is read the same as a number', () => {
  const stamp = (ms) => ({ toMillis: () => ms });
  eq(successionOrder([
    { userId: 'later', joinedAt: stamp(20) },
    { userId: 'earlier', joinedAt: stamp(10) },
  ]), ['earlier', 'later'], 'the order');
});

test('a malformed row is skipped rather than crashing the handover', () => {
  // A membership row read back as missing comes through as `{userId}` with
  // nothing else; a null in the list must not take the set list down with it.
  eq(pickSuccessor([null, undefined, { succession: 1 }, { userId: 'real' }], 'owner'),
    'real', 'the heir');
});

console.log(`\n${ran - failures.length}/${ran} passed`);
if (failures.length) {
  console.log('\nfailures:');
  for (const [name, e] of failures) console.log(`  ${name}\n    ${e && e.stack}`);
  process.exit(1);
}
process.exit(0);
