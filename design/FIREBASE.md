# Firebase integration: sync, sharing and the rights gate

Design document, 2026-08-30. Revised 2026-09-04 for the 0.7 line: section 0 is
new and reconciles this document with the six principles the owner set for
multi-person work, section 13 is new, and sections 6.2, 6.3, 9.2 and 11 are
amended where those principles overturn a decision. Stage 0 is built; nothing
else in here has been.

Companion docs: `ARCHITECTURE.md` (the product design, written before the engine
moved on-device), `BACKLOG.md` (what was deferred), `design/NAVIGATION_SYSTEM.md`
(the IA this has to fit into, which already reserves a third tab slot for
sharing).

**The claim this document converges on:** the whole integration is worth doing
for one feature, a setlist several people can open and mark up, and that feature
is reachable in four shippable stages if one preparatory change lands first,
giving every document a stable identity that is not its title.

Three things in this document are measured rather than argued, and they drive
most of the recommendations:

- One real arrangement in the workspace, `sous-le-ciel-de-paris`, holds 29
  MusicXML versions totalling **16 MB**. Compressed individually, the same
  29 versions come to about **0.67 MB**. A 24:1 ratio, because consecutive
  versions of a score are nearly identical text.
- Pencil annotations are keyed `<slug>/<version>/p<N>` and stored as loose
  `.pkdrawing` files in the app's Documents directory. They are keyed to a
  version, so an arrangement op silently leaves the previous version's markup
  behind.
- The OMR service key and the OpenRouter key are baked into the app bundle at
  build time, shared by every install, with no per-user attribution.

Where this document says *verified*, it was read in the code or measured on
disk. Where it says *from the docs*, it came from Firebase's documentation and
carries a link. Everything else is labelled as an assumption or an open
question.

---

## 0. The principles this design now answers to

Added 2026-09-04, at the start of the 0.7 line. Everything below section 0 was
written on 2026-08-30 against a set of assumptions the owner has since replaced.
The measurements in section 1 and the platform research in section 10 are
unaffected and still stand. The *decisions* in sections 6, 9 and 11 are not, and
this section says exactly which ones changed and to what.

The six principles, as given:

> 1. LOCAL-FIRST; cloud OPTIONAL; no login should ever gate using the app.
>    Everything works offline/signed-out; cloud is additive.
> 2. The main goal: SHARED PLAYLISTS (setlists) where anyone in the playlist can
>    ADD arrangements and REORDER them.
> 3. Auth: GOOGLE SSO.
> 4. Permission model: anyone in the playlist can add / reorder / share with
>    others (sharing ADDS that person to the group that has access). But ONLY the
>    owner who created the setlist can DELETE the playlist.
> 5. What's shared must include ANNOTATIONS, and ALL setlist participants can
>    annotate.
> 6. There must be an option to share an arrangement OR a setlist with someone
>    else WITHOUT internet/cloud -- via AirDrop or other local means.

### 0.0 The six answers, 2026-09-08

The six open questions §12 recorded were put to the owner and answered. They are
quoted here because three of them overturn something this document decided, one
of them makes a permission model that was already implemented correct, and one
adds a feature with no design at all yet.

> 1. **COPYRIGHT:** ship with NO scores bundled, and sharing is limited to
>    groups of UNDER 12 people. That's the whole posture -- private small-group
>    sharing, no distribution of copyrighted content, no bundled library.
>    Enforce the <12-member cap on a shared setlist/group.
> 2. **PERMISSIONS:** only the ONE person who created the setlist (the owner)
>    can remove MEMBERS. ANY member in the setlist can remove PIECES/entries.
> 3. **INVITE / SHARING:** share by URL or QR code. Sharing must ALSO work with
>    NO INTERNET -- offline via AirDrop/local transfer + QR handoff, per
>    principle 6.
> 4. **OMR MONTHLY CAP:** none. No per-user OMR quota.
> 5. **OWNER DELETES ACCOUNT:** transfer setlist ownership to the NEXT person
>    who was invited to that setlist -- ownership passes down the invite order.
> 6. **OWN-LIBRARY SYNC:** in 0.7, not deferred to 0.8.

| # | What it settles | What changes |
|---|---|---|
| 1 | The rights posture, entire | **The cap is TWELVE including the owner** (§0.10), and **no build may bundle a score** -- which was not true and had to be fixed (§0.11). §8 and §12.8 are rewritten around a posture that is now stated rather than inferred |
| 2 | Who removes what | **Already implemented and now confirmed correct**: `membersMayRemoveEntries = true`, `membersMayRemoveMembers = false`, owner alone deletes the set list. §12.9 closes with no code change |
| 3 | How somebody joins | **URL and QR, and a fully offline path.** The URL exists; QR and the offline join are new. §13.5 is new and says what offline joining can and cannot mean |
| 4 | OMR quota | **No per-user cap.** §11.4's page cap is struck. Token attribution is NOT struck -- see §0.12 |
| 5 | Succession | **New.** Invite ORDER becomes stored, ordered data, and an owner deleting their account promotes the next-invited member. §6.6 is new; §12.6 closes |
| 6 | Own-library sync | **Moves into 0.7.** §11.7 was the last increment and is now inside the line rather than after it |

### 0.10 The cap is twelve, including the owner

Stated as an inequality twice -- *"groups of UNDER 12 people"*, *"the
<12-member cap"* -- and since confirmed: **max 12 including the owner.** Twelve
people in a group, not eleven. `SetlistPermission.membershipCap` is 12 and the
deployed `claimInvite` enforces 12, so no redeploy was needed for the number.

Recorded because this went the other way first, and the mistake is instructive.
Read cold, "<12" is eleven, and on a limit whose purpose is keeping private
sharing from becoming distribution the stricter reading looked like the right
default. It was not the intent -- and worse, the deployed Function already
enforced 12, so the eleven reading would have left the app permanently one
member below its own server: a group would fill to twelve while the UI still
offered to invite, and nothing would say why the invitation failed. **The
server's number was available the whole time and was the better evidence than
either reading of the sentence.**

It is enforced in exactly one place that can be trusted -- `claimInvite`, which
counts members inside a transaction -- because the security rules refuse every
client write to the membership map and the client's own constant is therefore
advisory. `testTheFunctionEnforcesTheSameCapThisAppShows` reads the number out
of `firebase/functions/index.js` and fails on a drift, for precisely the failure
above.

### 0.11 No score may be bundled, which was not true and is now

*"Ship with NO scores bundled."* This was already the intent and was not the
fact. The `Bake UI-test fixtures` build phase copied
`testdata/app-samples/` into the app bundle in **every configuration**, so
Release carried it too.

**Verified in the shipped artifact, not inferred.** 0.6.20 build 180 --
uploaded to TestFlight on 2026-09-08 -- contains
`Scoranger.app/samples-seed/` holding all four fixtures, 788 KB: two editions of
"Sous le ciel de Paris", a Hubert Giraud composition, one of them an arrangement
by Gheorghe Branici, as both `.mxl` and `.pdf`.

Nobody ever saw them; they are seeded only under `-seedTestLibrary`. They were
inside every copy of the binary regardless, which is distribution whether a
screen shows them or not.

**The comment is how it survived.** The phase said "NOT a shipped feature: a
fresh install starts with an empty library. These files exist only so the UI
tests have deterministic content." True of the LIBRARY, false of the BUNDLE, and
sitting directly above the two lines that did it. Prose is not a guard.

Fixed: the copy is gated on `$CONFIGURATION`, and a non-Debug build actively
removes any `samples-seed` an incremental build left behind. Proven with a
Release build. `check_no_bundled_scores.py` is the release gate and it inspects
the ARTIFACT, not only the script -- the script is what should be right, the
artifact is what ships.

Build 180 is internal TestFlight, to the owner and his son, of the owner's own
purchased material, so the practical exposure is his own music reaching his own
household. **It must not go to an external tester or to App Review as it
stands.** The next build does not carry them.

### 0.12 No OMR cap, and per-user cost tracking

Answer 4 struck the per-user monthly page cap: *"none. No per-user OMR quota."*
The follow-up settles what replaces it: *"I want PER-USER tracking of OMR
costs"* -- no limit, but every conversion attributable to a user.

So the token migration §11.4 called "not optional" stays, and the reason it
gave was always attribution rather than quota: one key compiled into every
install means any copy of the app can spend the owner's OMR budget and nothing
in a log says which. A bucket with no meter still has a bottom.

**Verification needs no credentials, and that shaped the implementation.** A
Firebase ID token is an RS256 JWT signed by Google and checked against Google's
PUBLIC certificates. `firebase-admin` is deliberately not used: its purpose is
privileged access this service must never have, and it is two orders of
magnitude larger than verification needs. One pinned dependency
(`PyJWT[crypto]`) for RSA, no service-account key, no ADC, nothing to rotate or
leak. `omr-service/identity.py` carries the checks explicitly -- `aud` against
this project, `iss` against its securetoken issuer, `alg` pinned to RS256 --
because those three are the ones a library will skip by default, and without
`aud` "verified" means only "signed by Google for somebody".

**Three outcomes, and the middle one is the design decision:**

| Request | Attributed as | Trust |
|---|---|---|
| Verified Firebase ID token | `uid:<sub>`, with the email for readability | `verified` |
| Valid shared API key, no token | `anonymous` | `unattributed` |
| A token that does not verify | **refused, 401** | -- |

The third row is the one worth stating: a bad token is never quietly downgraded
to anonymous. A downgrade would let anyone spend under a clean label by sending
rubbish in the `Authorization` header, which destroys the report the feature
exists to produce.

The second row is a **consequence of principle 1 and not a gap.** Importing a
scanned PDF is a core signed-out feature, and no login may gate using the app,
so there is genuinely no user to attribute those jobs to. The report says
`unattributed` rather than implying the attribution broke. **If the owner wants
every job attributable, OMR would have to require an account -- which breaks
principle 1.** That trade-off is his to make; it is not made here.

**The record is a structured log line, not a database.** One JSON line per
finished job carrying `omr_usage`, the actor, pages, seconds and outcome. On
Cloud Run stdout is the durable store: Cloud Logging ingests it and aggregates
by any field, and it survives the instance dying, which an in-process counter
does not -- this service keeps jobs in process memory precisely because nothing
in it is meant to be durable. It bills on **every** exit path including
`timeout` and `unreadable`, because a PDF Audiveris cannot read is exactly the
one it grinds on for eight minutes, and counting only successes under-reports
the expensive cases.

Progress polls are not attributed: the app polls roughly once a second while a
bar moves, and verifying a token per poll would turn one RSA check per job into
hundreds -- and a token expiring mid-conversion would break the progress bar of
a job that is running fine.

*Deploy order matters and the service says so out loud.* Without
`FIREBASE_PROJECT_ID` nothing verifies, so every signed-in request 401s while
signed-out ones keep working -- a misconfiguration that reads as "sharing broke
for people with accounts". The boot log names the exact
`gcloud run services update --update-env-vars` that fixes it, and `deploy.sh`
records why it must be `--update-env-vars` (merges) and never
`--set-env-vars` (replaces, and would wipe `OMR_API_KEY`).

### 0.1 What each principle changes

| # | The principle | What the 2026-08-30 document said | What it says now |
|---|---|---|---|
| 1 | Local-first, no login gate | §9.1 already recommends exactly this: no anonymous auth, no Firebase SDK until sign-in | **Unchanged, and promoted from a recommendation to an invariant with a named check.** §0.2 |
| 2 | Shared setlists are the goal | §11 spends stage 1 on whole-library multi-device sync and reaches sharing at stage 2 | **Re-sequenced. Sharing ships first; own-library backup ships after.** §11, rewritten |
| 3 | Google SSO | §9.2: "Sign in with Apple, and only that" | **Google SSO is the primary method, and Sign in with Apple ships beside it because Google SSO obliges it.** §9.2, amended |
| 4 | Members add, reorder, invite; owner alone deletes | §6.2: three roles, and "inviting stays with the owner in v1" | **Two roles. Every member adds, reorders, invites and annotates. The owner alone deletes the setlist.** §6.2, replaced |
| 5 | Shared annotations, everyone annotates | §6.3 recommends personal layers, and §11 defers them to stage 3, after a read-only stage | **Annotations are part of the headline feature, not a later stage. Per-participant layers, merged at render.** §6.3 amended, §11 rewritten |
| 6 | Share without the cloud | Absent. The document has no offline sharing path at all | **New section 13. It ships before any cloud work.** |

Three of these are genuine reversals of a recommendation the document argued
for, and each is recorded at the section it overturns rather than only here.

### 0.2 Principle 1, made checkable

The document's §9.1 recommendation and this principle agree, so the work is not
to change a decision but to stop it eroding. A property that is true today
because nobody has had a reason to break it yet is not an invariant; it is a
coincidence with good luck.

Three things make it one:

**No screen may require an account.** Every screen the app has today works
signed out and continues to. The sharing screens are the only new screens that
need an account, and they are reached from a tab that, signed out, explains what
signing in would add and offers the offline bundle share (section 13) instead of
a wall. A signed-out user is never shown a modal, a redirect or a disabled tab.

**Signed out, the app makes no Firebase contact of any kind.** Not anonymous
auth, not App Check, not a configuration call. `FirebaseApp.configure()` runs at
first sign-in and not at launch. This is §9.1's recommendation and it is what
makes the promise literal rather than approximate.

**A check asserts both.** `check_signed_out.py` for the engine half -- the
`JournalingRepository` is not constructed, no `sync.db` is created, no `rev`
appears on any document -- which `check_sync.py` already covers and which moves
under a name that says what it protects. A UI test walks every screen with no
account and asserts none of them blocks. Both are release gates, and both fail
if someone later reaches for anonymous auth as a convenience.

Signing out is not a deletion. The library stays, the app keeps working, and the
sign-out confirmation says so in those words.

### 0.3 Principle 2, and what it costs to honour

Taking "shared playlists are the main goal" seriously means the execution plan
in §11 was ordered wrong for this product, and the reordering is the largest
change in this revision.

The 2026-08-30 plan reached sharing at stage 2 because stage 1 -- one user's
library on two of their own devices -- exercises the whole sync spine with no
concurrency and nobody else's data at stake. That is good engineering sequencing
and the argument for it is honest.

It is also two or three shippable increments of work before the goal is
reachable, and **the shared setlist does not depend on any of it.** That is
worth stating plainly because it is not obvious: a shared setlist entry is a
*copy* of a pinned version into `shared/{setlistId}/…` (§4.3), authorised by the
setlist's own membership map. It never reads the sharer's `libraries/{libraryId}`
documents. Nothing in sections 6, 8 or 13 requires the library mirror, the
holding policy, eviction, or the two-libraries screen of §9.3.

So the dependency the old plan implied is not real, and the new order in §11
ships the goal first. What the reordering genuinely costs:

- **Concurrency arrives before the spine has been shaken down on one user.**
  The first multi-writer code to ship is the shared setlist itself. Mitigated by
  the fact that the shared surface is small and its hardest parts are already
  chosen to be conflict-free by construction: immutable entries, a fractional
  index per entry (§6.5), and per-participant ink (§6.3).
- **Own-library backup is later, so a lost or replaced iPad is unprotected for
  longer.** The offline bundle (section 13) is a partial answer -- a user can
  export their library to Files or a Mac -- and it is a real one, but it is
  manual. Say so rather than implying 0.7 protects anyone's library.

Both are acceptable. Neither is invisible, and the second is the one to tell the
owner about.

### 0.4 Principle 3, and the obligation it creates

Google SSO triggers App Store Review Guideline 4.8, and the 2026-08-30 document
had already found this while arguing the other way (§10.2): the guideline
obliges an equivalent privacy-preserving login option **only when a third-party
or social login is offered**, which is precisely why that document recommended
Sign in with Apple alone.

Choosing Google SSO therefore means shipping two sign-in methods, not one. Sign
in with Apple satisfies the obligation and is the cheapest way to satisfy it,
because it needs no password handling and no email verification of our own.

This is a cost of the principle, not an argument against it, and there is a
straightforward reason to accept it: the people this product shares with are
bands and ensembles, and an invitation addressed to a Google account is an
invitation addressed to the address they already use. Sign in with Apple's Hide
My Email, which the old document counted as an advantage, is an obstacle to
invitation by email -- a member who signs in with a private relay address cannot
be found by the address their bandmates know them by. Section 6.2's invitation
flow has to handle that case, and it is section 12.10.

**Decision recorded: Google SSO primary, Sign in with Apple offered beside it,
both landing on the same Firebase Auth user record.** Anonymous auth remains
rejected, for §9.1's reasons, which principle 1 strengthens rather than weakens.

### 0.5 Principle 4, and the two questions it leaves open

Ali's model is flatter than §6.2's and the flattening is deliberate: a band's
running order is edited by the band, and a permission system that makes one
person the bottleneck on adding a tune is a permission system nobody will use.

What the principle settles:

| | Read | Annotate | Add entry | Reorder | Invite | Delete the setlist |
|---|---|---|---|---|---|---|
| Member | yes | yes | yes | yes | yes | **no** |
| Owner | yes | yes | yes | yes | yes | **yes** |

What it does not settle, and what §12.9 asks the owner:

- **May a member remove an entry another member added?** Recommended yes: a
  setlist that anyone can add to and nobody can prune fills with mistakes, and
  the act is visible and undoable. Removal is soft, the entry keeps its ink, and
  the person who removed it is recorded.
- **May a member remove another member?** Recommended no. Removing people is the
  act with rights consequences, it is the mirror of deleting the setlist, and it
  belongs with the owner. A member may always remove *themselves*.

The `role` field stays in the data model with three values even though only two
are issued, because a reader role -- hand a dep player the set, they mark their
own part, they cannot reorder anything -- is the first thing a working band will
ask for, and adding a value to an existing field is cheaper than introducing the
field later.

**The membership cap of twelve (§8.2) matters more under this model, not less.**
Owner-only invitation was itself a brake on growth; member invitation removes it,
so the cap is now the only structural limit between a band and a distribution
list. It stays, it is enforced in the security rules rather than the client, and
every invitation records who issued it.

### 0.6 Principle 5, and the layer question answered

The principle asks for two things: what is shared includes annotations, and all
participants can annotate. §6.3 already describes a design that delivers both,
and the change is one of sequencing and of picking the recommended shape rather
than leaving it open.

**Recommendation: per-participant layers, merged at render. Not one shared
canvas.**

Each participant owns one ink document per entry (`ink/{userId}`), writes only
their own, and reads everyone's. The page composites every layer the viewer has
switched on, each in that participant's assigned colour. Everybody annotates,
everybody sees everybody's marks, and there is no merge function anywhere in it
because no two people ever write the same document.

Why this rather than the single shared canvas of §6.3's "band layer":

- **It is conflict-free by construction**, not by a CRDT that has to be right.
  The band layer's grow-only stroke set is a sound design and it is still in the
  document, but it is a per-stroke Firestore document with a compaction cycle,
  and it is the one part of this feature that can be subtly wrong in a way a test
  suite might miss.
- **It answers "who wrote that?"**, which on a band's chart is most of the
  question. A merged canvas loses authorship the moment two people draw.
- **A participant can always clear their own marks** without touching anyone
  else's, which on a shared canvas is not expressible.

The visibility control is three states, not a per-person checklist: mine only,
everyone's, or one person's. Default everyone's, because the point is to see the
band's marks.

**The band layer stays deferred**, and §6.3's analysis of it stays in the
document unchanged, because if per-participant layers prove to be the wrong
shape the reason will be a specific one and the alternative is already worked
out. Note that §6.3 gated the band layer on the editor role, which principle 4
removes; if it is ever built, every member can write it.

Annotations travel in the offline bundle too (section 13). A principle that says
what is shared includes annotations does not stop applying because the sharing
went over AirDrop.

### 0.7 Principle 6, which the old document did not consider

Section 13, new. The short version: an arrangement or a setlist exports as a
single self-contained file containing its documents, its artifacts and its
annotations, and the receiving device imports it with no account and no network.

Two things make it more than a convenience feature, and they are why it ships
first:

**It is the only part of 0.7 that is pure gain under principle 1.** No account,
no Firebase project, no rules, no bill, nothing to deploy. A user who never signs
in gets a way to hand a bandmate a chart.

**It defines the wire format the cloud share then reuses.** A shared setlist
entry and a bundle entry carry the same thing: a pinned version's bytes, its
document, and its ink. Building the bundle first forces that payload to be
written down and round-tripped through a test before any of it is also a
Firestore schema.

The rights question does not go away, and section 13.5 treats it: AirDrop of a
publisher's scan to one bandmate is a materially different posture from a copy
on a service operator's servers, but "materially different" is not "no
question", and the book ban of §8.2 extends to bundles.

### 0.8 What did not change

Worth listing, because a reconciliation that appears to touch everything invites
re-litigation of the parts that were right:

- **Section 2**, the sync layer in Swift with the engine kept ignorant of
  Firebase. Principle 1 is the argument for it, and it was already made.
- **Section 3 and stage 0**, opaque identity. Principle 2 needs it more than the
  old plan did: a shared setlist entry addresses `(scoreUid, versionUid)`.
- **Sections 4.3, 5, 7, 8, 10.** The storage layout is dictated by the
  two-document rule-lookup cap, the network tiers by artifact sizes, the conflict
  rules by immutability, the rights gate by the library's contents, and the
  platform facts by Firebase's documentation. None of the six principles bears on
  any of them.
- **The rejection of anonymous auth** (§9.1, §12.4). Principle 1 makes it
  stronger.
- **The rejection of public share links** (§8.2 guard rail 1). Principle 4 says
  sharing adds a *person* to the group, which is the same rule arrived at from
  the other direction.

### 0.9 The infrastructure boundary

Nothing in this document authorises touching a live service. Recorded at the top
because it is a standing constraint on the whole 0.7 line, and repeated
concretely at §11.8.

No Firebase project is created, no security rules or Cloud Function are
deployed, no `omr-service` deployment is changed, and no project ID, bucket
name, reversed client ID or `GoogleService-Info.plist` is committed or pushed --
until the owner says so, per increment. The first increment that needs a project
to exist is 0.7.2; the first that needs anything deployed is 0.7.3. 0.7.0 and
0.7.1 clear the boundary entirely and can be built and shipped without it being
lifted.

---

## 1. What is in the code today

### 1.1 The Firestore-shaped claim, checked

`engine/scoranger_engine/db.py` opens with the promise that the backend swap is
mechanical: implement `FirestoreRepository` against the same interface, point
artifact references at a bucket, replace the manifest projection with listeners.
`CLAUDE.md` repeats it.

The *document shapes* live up to it. Scores, versions, sources, pieces,
setlists and books are all plain JSON dictionaries with no SQL-shaped
denormalisation, versions are a real subcollection keyed by score, artifacts are
referenced by relative filename and never stored in the database, and the
manifest is already a separate projection rather than the source of truth. That
part of the design paid off and should be said plainly.

Four things in the current code do not live up to it, and they are the stage 0
work:

**There is no injection point.** `workspace._repo()` constructs
`SqliteRepository` directly, holds it in a module-level singleton, and is
annotated as returning that concrete class. No protocol, no factory, no
parameter. Swapping the repository today means editing `workspace.py`, which is
the one module every op goes through. This is small to fix and it should be
fixed before anything depends on it.

**Identity is the title.** A score's document ID is `slugify(name)`, and
`rename_slug` exists precisely because that ID has to change when the title
does: it renames the artifact directory, re-keys every version and source row,
and rewrites the slug inside every piece's ordering, in one call. That works in
a single-process SQLite file. Across two devices it is a fan-out rewrite of
documents another device may be concurrently appending to, and across two users
it is a global namespace where both of them own `morrisons-jig`. The stated
migration path cannot survive it.

**Version IDs are allocated by counting.** `_write_version` computes
`seq = len(repo.list_versions(slug)) + 1` and formats `v{seq:03d}`. Read, then
write, with no transaction. Two devices offline on the same arrangement both
produce `v031`, and one of them has to lose or be renamed.

**The engine cannot hold Firebase credentials.** This is the one that retires
the stated plan outright, and it is a consequence of a decision taken after
`db.py` was written: since 2026-08-15 the engine runs *on the device*, embedded
CPython 3.14 inside the app, with `music21` as its only dependency
(`engine/pyproject.toml`). `firebase-admin` is a server SDK that authenticates
with a service-account key; putting one in a shipped app hands every install
full write access to every user's data. Firestore does have a REST API that
accepts a Firebase Auth ID token, so a Python `FirestoreRepository` on device is
*possible* rather than impossible, but it would put a network call behind every
document read on a device whose defining requirement is working offline, and it
would re-implement the offline cache that `firebase-ios-sdk` already ships.

So: **`FirestoreRepository` behind `SqliteRepository`'s interface is the wrong
plan, and the note promising it in `db.py` and `CLAUDE.md` should be replaced
rather than left to mislead the next reader.** What replaces it is section 2.

### 1.2 Artifact sizes, measured

Versions are no longer uniformly small MusicXML, and the three kinds behave
differently enough that one sync policy cannot cover them.

| Kind | Where it comes from | Measured / reported size | Compresses |
|---|---|---|---|
| Notation version | every arrangement op | 510–645 KB each, 29 of them in one arrangement, 16 MB total | yes, 24:1 |
| PDF arrangement | `create_pdf_score`, `extract_from_book` | a few pages of a scan | no |
| Book | `create_book` | one reported at 52 MB | no |
| Source | `add_source` | another edition, MusicXML | yes |
| Annotation | `DrawingStore` | one `PKDrawing` blob per page | already compact |

Verified by measurement on `workspace/sous-le-ciel-de-paris`: 29 files,
552,373 bytes for `v001`, 23,302 bytes when gzipped at level 9, and 605,878
bytes for the whole chain compressed. Reported but not verified by me: the 52 MB
book, which is on the owner's device and not in this checkout.

Two conclusions fall straight out.

**Compress notation artifacts before anything cleverer.** Storing versions
gzipped in Cloud Storage takes one arrangement's history from 16 MB to under a
megabyte. That is most of the sync-volume problem solved by a decision that
costs nothing and breaks nothing, because MusicXML is text and `.mxl` is already
a zip of exactly this content. Do this in stage 1.

**Reject delta chains.** A binary delta between consecutive versions would be a
few hundred bytes, which is tempting and wrong: a delta chain means a device
cannot fetch `v017` without first fetching `v001` through `v016`, which is the
exact opposite of what a device that only ever opens the latest version needs.
Gzip captures nearly all of the win with none of the coupling.

**Books get their own policy.** A single 52 MB file that is a reference work,
not an arrangement, is the worst possible thing to sync by default and the
highest rights risk in the library. See section 8.

### 1.3 Annotations

`DrawingStore` (in `ios/Scoranger/ScorePagesView.swift`, around line 791, and
its own comment says "server sync is a later feature") writes one
`.pkdrawing` file per key into `Documents/annotations/`, with the key
`<slug>/<version>/p<index>` flattened by replacing slashes with underscores.

Three properties of this matter for the design, all verified:

**Page indices are device-independent.** `VerovioRenderer` lays out at a fixed
US Letter page, 2159 x 2794 tenths of a millimetre at scale 45, not at the
device's width. Page 3 of `v012` is the same page 3 on an iPhone and on a
12.9-inch iPad. Annotations are therefore portable between devices without
re-flowing anything, which is what makes annotation sync tractable at all.
Continuous layout has no pages and `design/CONTINUOUS_VIEW.md` already records
that ink is unavailable there.

**The eraser is a vector eraser.** `AnnotationController.pkTool` returns
`PKEraserTool(.vector)`, which removes whole strokes. That is a design choice
made for aiming on a dense score, and it happens to be the property that makes a
conflict-free multi-user ink model possible (section 6.3). A pixel eraser would
have made it a research project.

**Annotations do not follow the music forward.** The key contains the version
ID, and nothing carries a drawing from `v030` to `v031`. Run a transpose on an
arrangement you have marked up and your markup is still there, on the version
you can no longer see by default. This is a live wart today, and it becomes a
much worse one in a shared setlist, where one person running an op would appear
to erase everyone's marks. Section 6.1 answers it inside the sharing model
instead of leaving it as a bug to fix later: a shared setlist pins a version.

### 1.4 Keys and cost exposure

`ios/project.yml` has two build phases, "Bake OMR key" and "Bake OpenRouter
key", that copy `.omr-api-key` and the `OPENROUTER_API_KEY` from `.env` into the
app bundle. The comments say why: the repo is public and this gives zero-config
conversion and chat. `omr-service/README.md` deploys Cloud Run with
`--allow-unauthenticated` and gates on that one shared header key.

This is a sensible posture for a prototype with one user and an untenable one
the moment there are accounts. Today there is no way to know which install spent
the CPU-seconds, no way to rate-limit one abuser without cutting off everyone,
and the key is extractable from any distributed build. Accounts are what make
this fixable, and fixing it belongs in the same stage that introduces them, not
in a later "quotas" stage.

### 1.5 What moved between 42b6fa3 and 0.5.4

This document was written against `dev` at 42b6fa3. Re-read against ef27426,
five things it says are now wrong or incomplete, and one is a new constraint
rather than a correction. Everything else in section 1 still measures true:
`DrawingStore` is still slug-keyed at `ScorePagesView.swift:792`, the two baked
keys are still in `ios/project.yml`, and page indices are still
device-independent.

**A piece carries its own credits now.** §4.2 lists `pieces/{pieceUid}` as
`name, order`. A piece also has `composer`, `arranger` and `tags`
(`set_piece_metadata`, `all_tags`), and for a library of scans that is the only
place a composer can live -- a PDF arrangement has no notation to carry one.
Those three fields sync like any other, but the tags list is the first
collection-wide vocabulary in the model: `all_tags()` is computed over every
piece, so a device with a partial library computes a different filter list.
Recompute it from the pulled documents, never cache it.

**A whole library now arrives at once.** `bulk-import` (Import Folder) creates
a piece per folder and an arrangement per file in one act; the owner's Newzik
library is 43 pieces and 111 artifacts. §10.1's tightest free-tier limit is
5,000 Cloud Storage **uploads** a month, and an import of that size is ~110 of
them in a minute. It fits, and it is the burst the artifact queue has to
survive being interrupted in, which the plan assumed would only ever happen to
a book.

**A startup migration writes documents.** `applyBundledMetadataIfNeeded` runs
on launch, matches the bundled Newzik metadata onto pieces by name and writes
composer, arranger, tags and renames. It is gated on a `UserDefaults` flag,
which is **per device, not per library**: with sync on, the second iPad runs it
again over a library the first already migrated. This one converges, because it
fills in rather than overwrites and a renamed piece no longer matches. The
general shape does not: a migration that is not idempotent becomes a fan-out of
conflicting writes, once per device, on every launch. Any future one belongs
behind a flag stored in the library, not in `UserDefaults`.

**Nothing in the app decodes `uid`.** Stage 0 put a `uid` on every score,
piece, setlist, book and source and into the manifest, and no Swift model has
a field for it -- `ScoreDoc`, `PieceDoc`, `SetlistDoc` and `BookDoc` are still
keyed on the slug alone. That is fine while everything is local and is the
first thing stage 1 needs, since a share and a push both address the uid.

**The status line has a home.** §5.3 asks for one line saying what is waiting
and when it last synced. `NoticeBar` (`Navigation/Screen.swift`) is that
control; it did not exist when this was written.

---

## 2. Where the sync layer lives

The decision that shapes everything else.

**The local SQLite database and the artifact files stay authoritative for the
device. A sync layer written in Swift mirrors documents to Firestore and
artifacts to Cloud Storage, and applies incoming remote changes by calling the
same bridge ops the UI already calls. Nothing in `engine/` gains a Firebase
dependency, or knows Firebase exists.**

```
   ┌────────────────── the device ───────────────────┐
   │                                                 │
   │  SwiftUI  ──manifest poll──►  PythonEngine      │        Firestore
   │     │                          (bridge.py)      │      documents only
   │     │                              │            │            ▲
   │     │                        SQLite + files     │            │
   │     │                              │            │      ┌─────┴──────┐
   │     └──────────►  SyncCoordinator ─┘────────────┼─────►│  Firebase  │
   │                    (Swift, new)                 │      │  iOS SDK   │
   │                         │                       │      └─────┬──────┘
   │                    artifact cache                │            ▼
   └─────────────────────────────────────────────────┘     Cloud Storage
                                                             artifacts
```

Why not the alternatives:

**Firestore as the client's database**, the shape a normal Firebase app takes,
would mean the engine reads and writes through the iOS SDK. It cannot: the
engine is Python, it needs real files on a real filesystem for music21, and
every op would have to cross the Swift/Python boundary twice per document. The
offline cache would also stop being a working copy and start being a cache of a
remote authority, which is precisely the thing the product owner ruled out.

**Server-first, engine on Cloud Run**, which is what `ARCHITECTURE.md`
originally described, contradicts a locked decision and undoes the 0.4 work that
made the iPad standalone.

What this choice buys, concretely: **the offline path is the existing code
path.** Signed out or on a plane, `SyncCoordinator` is not running and the app
behaves exactly as it does at 42b6fa3. Offline is the mode the app is written
in, with an optional mirror attached, which is the only way to honour "usable
like an old school app with just local files" without maintaining a second
implementation of everything.

The cost of the choice, stated honestly: the sync layer is real, new,
Swift-only code with no Python test harness, and the repo's verification culture
lives in `engine/scripts/check_*.py`. Every stage in section 11 therefore names
what proves it, and two of those proofs need a Firebase emulator suite that does
not exist yet.

---

## 3. Identity, and why it is stage 0

Sharing needs three kinds of name, and today the code has one.

| Name | What it is for | Today | Needed |
|---|---|---|---|
| Slug | the filesystem path, the chat handle `arr:<slug>` | `slugify(title)`, changes on rename | unchanged, stays local |
| Document ID | what Firestore keys on, what a share points at | none | a ULID, assigned once, never changes |
| Display label | what a person reads (`#3`, `v012`) | derived for `#N`, *is the ID* for `vNNN` | derived for both |

Three additive changes, none of them user-visible, all of them cheap now and
expensive later:

**Every score, piece, setlist and book document gets a `uid` at creation.** A
ULID, assigned in `create_score`, `create_pdf_score`, `create_piece`,
`create_setlist` and `create_book`, and never rewritten. `rename_slug` keeps
doing exactly what it does to the local filesystem and to local references, and
becomes invisible to sync, because sync never held the slug.

**Version IDs become opaque, and `vNNN` becomes a label.** `_write_version`
assigns a ULID instead of counting, keeps `seq` as the display ordering, and
`vNNN` is computed from `seq` for display and for the CLI's convenience. Two
devices can then both append a version offline and neither has to lose or be
renumbered, because they were never competing for the same name.

This is the invasive one. `vNNN` appears in the CLI's `--version` flag, in
`bridge.py`, in `AppState.pinnedVersion`, in the annotation key, in
`ScoreArtifact` filenames and in `CLAUDE.md`. The alternative is to keep `vNNN`
as the ID and resolve collisions at sync time by renumbering the loser, which
works, is cheaper this week, and leaves a permanent trap: a version ID that
means different things on two devices until they meet. **Recommendation: do the
opaque IDs now.** The library is small, the check suite is unusually strong, and
`check_workflows.py` plus `check_undo.py` will catch a bad rename. This is the
single decision in this document most likely to be deferred and most expensive
to defer.

**The annotation key stops containing the slug.** `<scoreUid>/<versionUid>/p<N>`
instead of `<slug>/<version>/p<N>`, which deletes `DrawingStore.rename` and its
whole class of orphaning bug along with it.

Stage 0 also introduces the injection point: a `Repository` protocol in `db.py`
that `SqliteRepository` conforms to, and `workspace._repo()` reading a
module-level factory. Not because a `FirestoreRepository` is coming, but because
a `SyncJournalRepository` that wraps SQLite and records what changed is how the
Swift layer learns what to push without diffing the whole manifest every two
seconds. See section 4.1.

---

## 4. The data model

### 4.1 What the local database gains

One new table, and one new field on the existing documents.

`changes(seq INTEGER PRIMARY KEY AUTOINCREMENT, collection TEXT, doc_id TEXT,
op TEXT, at TEXT)` is an append-only journal written by the repository wrapper
on every `set_*`/`delete_*`. The Swift sync layer keeps a cursor into it and
pushes what is past the cursor. Without it, the only way to know what changed is
to diff `manifest.json` against a remembered copy every poll, which is both
lossy (the manifest is a projection and drops fields) and quadratic in library
size.

Every synced document gains `rev`, a monotonically increasing integer bumped on
every local write, and `synced_rev`, the value at the last successful push.
`rev != synced_rev` means dirty. This is the smallest thing that makes "what do
I still owe the server" answerable after a crash.

Neither is exposed to the user, the CLI or chat.

### 4.2 Firestore collections

```
users/{userId}
    displayName, createdAt, libraries: [libraryId], quota: { omrPagesThisMonth, resetAt }

libraries/{libraryId}
    owner: userId, name, createdAt
    scores/{scoreUid}       name, title, composer, arranger, piece, latest,
                            created, deletedAt, rev, artifactKind
        versions/{versionUid}   seq, op, args, parent, time, parts, turn,
                                storagePath, bytes, sha256
        sources/{sourceUid}     name, origin, storagePath, parts
    pieces/{pieceUid}       name, order: [scoreUid]
    setlists/{setlistUid}   name, order: [scoreUid]        (the private kind)
    books/{bookUid}         name, pages, storagePath, syncEnabled

setlists/{sharedSetlistId}                                  (the shared kind)
    name, ownerId, createdAt, members: { userId: "owner"|"member"|"reader" },
    memberIds: [userId], rightsAcknowledged: [...]
    entries/{entryId}       order (fractional index), title, composer,
                            scoreUid, versionUid, mode: "copy"|"reference",
                            storagePath, pages, addedBy, addedAt,
                            removedAt, removedBy
        ink/{userId}            layer: "personal"|"band", updatedAt, compactedRev,
                                pages: { "3": <PKDrawing bytes>, ... }
            strokes/{strokeId}  page, data (one-stroke PKDrawing), createdAt,
                                deletedAt        (band layer only)

memberships/{userId}_{sharedSetlistId}
    setlistId, userId, role, setlistName, joinedAt

invites/{inviteId}                                          (added 2026-09-04)
    setlistId, setlistName, emailLower, invitedBy, invitedAt,
    acceptedAt, acceptedBy, revokedAt
```

Four shapes in there are decisions rather than transcription.

**Shared setlists are top-level, not nested under a library.** A shared setlist
belongs to nobody's library; it is a thing several libraries point into. Nesting
it under the owner's library would mean every security rule on every entry and
every ink document walks up to a `get()` on the parent, and Firestore rules
charge for those lookups and cap them per request. Top-level, the rule reads
`resource.data.members[request.auth.uid]` off the document in hand.

**`memberships/` is a flat index that duplicates the membership map.** It exists
so "what setlists am I in" is one indexed query on `userId`, instead of a
collection-group scan or an `array-contains` over every setlist in the system.
It is denormalised on purpose and written by the same Cloud Function that
changes membership, never by a client. `memberIds` stays on the setlist as well,
because rules can read it cheaply and the client needs it to render who is here.

**`entries` hold `(scoreUid, versionUid)`, not `scoreUid`.** Section 6.1.

**`invites/` addresses a person who may not have an account yet** (added
2026-09-04, principle 4). Under owner-only invitation the owner could be asked to
wait until their bandmate had signed up. Under member invitation, at a rehearsal,
that is not a workable flow. An invite is therefore written against a lowercased
email address rather than a user ID, and it is claimed on the invitee's next
sign-in.

Two ways to claim it, and the choice is §12.11:

- **A callable Cloud Function** does the membership write, checks the cap, writes
  `memberships/` and stamps `acceptedBy`. Clean, server-authoritative, consistent
  with §4.4's rule that membership is decided by the server, and it means
  deploying a function.
- **Security rules on the verified email**, allowing a signed-in user whose
  `request.auth.token.email` matches an open invite to add only themselves to
  `memberIds` and `members`. No function to deploy. It needs the rule to be
  exactly right, it cannot enforce the cap as cleanly, and it rests on
  `email_verified` being true, which Google SSO gives and which has not been
  checked in the emulator.

*Recommendation: the Cloud Function.* Membership is the one place §4.4 already
names the server as authoritative, and a rule that lets a client write itself
into someone else's membership map is the highest-consequence rule in the system
to get subtly wrong. It is also the first thing in this plan that deploys
anything, which is why it is a question and not a decision.

An invite carries the setlist's name so the invitee sees what they are joining
before they join it, and nothing else about the setlist: an unaccepted invite
must not be a read grant.

### 4.3 Cloud Storage layout

```
libraries/{libraryId}/scores/{scoreUid}/{versionUid}.musicxml.gz
libraries/{libraryId}/scores/{scoreUid}/{versionUid}.pdf
libraries/{libraryId}/scores/{scoreUid}/sources/{sourceUid}.musicxml.gz
libraries/{libraryId}/books/{bookUid}.pdf
shared/{sharedSetlistId}/{entryId}/{versionUid}.{musicxml.gz|pdf}
```

The `shared/` prefix holds **copies**, made once when an entry is added to a
shared setlist and never updated in place. That is a deliberate duplication of
bytes. It buys three things: an entry is immutable so nobody's page moves under
them mid-gig, a member's read permission is a property of the path rather than
of a chain of lookups into someone else's private library, and revoking a share
is a delete of one prefix rather than a permission audit.

The path shape is not cosmetic. A Cloud Storage rule may read at most **two**
Firestore documents per evaluation (section 10.1), so authorising a shared
artifact has to be one lookup keyed on something the path itself carries. Hence
`shared/{sharedSetlistId}/…` with the membership map on
`setlists/{sharedSetlistId}`: the rule reads one document and is done. Any
layout where the artifact path did not name the setlist, or where membership
lived in a subcollection, would need a traversal the rules cannot perform, and
the whole thing would fall back to a Cloud Function minting signed URLs.

An entry in `reference` mode has no artifact under `shared/` at all. That is the
rights gate's main mechanism and it is section 8.

**Ink is not in Cloud Storage.** A page's `PKDrawing` is tens of kilobytes, well
under Firestore's 1 MiB document limit, and putting it in Firestore buys three
things Storage cannot: it rides Firestore's own offline write queue instead of
the app's artifact upload queue, it is authorised by the same rule as the
document it belongs to rather than by a second system, and it does not spend
against Cloud Storage's monthly upload allowance, which is the tighter of the two
free-tier limits (section 10.1). Storage is for artifacts that are large or
opaque; annotations are neither.

### 4.4 What is authoritative for what

| Thing | Authoritative | Notes |
|---|---|---|
| Notation, the bytes of a version | the artifact file, everywhere identical | immutable once written; `sha256` on the version document makes that checkable |
| A score's title, composer, arranger | the *notation*, projected onto the document | already true today; `set_metadata` writes both, and sync must never write a title to Firestore that the artifact does not carry |
| Local library membership and order | the device's SQLite, mirrored up | LWW per field, section 7 |
| A shared setlist's membership and order | **Firestore** | the one place the server is authoritative, because it is the only place two people can both be right |
| A member's personal ink | that member's device, mirrored up | nobody else ever writes it |
| The band's shared ink | **Firestore**, as an append-only stroke set | section 6.3 |
| Quota counters | **the server**, written by the OMR service | never by a client |

The one asymmetry worth naming: the local library is a local-authority system
mirrored to the cloud, and a shared setlist is a cloud-authority system cached
locally. They are different animals and the app should not pretend otherwise.
Concretely, a shared setlist you cannot reach is read-only until you can, and it
says so, whereas your own library is fully editable offline forever.

---

## 5. The sync design

### 5.1 What syncs, and when

**Documents always, both directions, immediately.** Everything in section 4.2 is
kilobytes. Pushing is driven by the change journal (section 4.1) as a batched
write, which is the one atomic primitive that works offline. Pulling is where
the interesting constraint lives.

**Listeners are scarce, and only on what is live.** Firestore bills a listener
that has been disconnected for more than thirty minutes as a brand-new query on
reconnect (section 10.1), which for an app designed to be offline is the
dominant cost variable. So:

- **A snapshot listener on the shared setlist that is currently open, and
  nothing else.** It is small, it is genuinely live, and it is open for minutes
  at a time, not days.
- **The library pulls with an explicit query, not a listener:**
  `where rev > lastSeenRev`, run on foreground, after a push, and on a slow
  timer. The `rev` field from section 4.1 exists exactly so this query is small
  and indexable. Reopening the app after a week offline costs one query
  returning the handful of documents that changed, not a re-read of the library.
- **Never a listener on a collection group, and never one on artifacts.**

This is a deliberate departure from the reflex Firebase shape, where everything
is a listener. The manifest poll the app already runs every two seconds is the
local equivalent and it stays; what changes is that the manifest can now change
because of something another device did.

**Artifacts on a holding policy, never wholesale.** A device holds:

1. the artifact of every score's **latest** version,
2. any version the user has **pinned** (`AppState.pinnedVersion`) or opened in
   the last N days,
3. every artifact of every score in a setlist the user has marked **offline**,
4. nothing else, until asked.

Everything not held is a row in the version history with a download affordance.
The version list is a document, so history stays complete and browsable offline
even when the bytes are not there. Measured against `sous-le-ciel-de-paris`,
this and gzip together are the difference between 16 MB and 23 KB for a device
that only ever plays the current version, and they are what makes the immutable
version chain affordable at all.

**Books are opt-in per book, and off by default.** `books/{bookUid}.syncEnabled`
defaults to false. A book is one enormous file, it is reference material rather
than work, and it is the highest rights risk in the library (section 8). The
affordance is a switch on the book screen reading "keep this book on my other
devices", and turning it on is a decision the owner made.

**Annotations sync with the artifact they mark.** A personal ink layer is small
and belongs to one person; there is no reason to withhold it.

### 5.2 Network policy

Three tiers, and the middle one is the only interesting one:

- **Any connection, including cellular:** all documents, all ink. Kilobytes.
- **Wi-Fi by default, cellular on explicit request:** notation artifacts.
  Compressed, a whole arrangement's current version is about 25 KB, so this
  could arguably be tier one; keeping it in tier two costs a musician nothing
  because the setlist they marked offline is already downloaded, and it protects
  the case of a first sign-in on a new device on a train.
- **Wi-Fi only, no automatic transfer, ever:** books and PDF arrangements over a
  size threshold. A 52 MB book must never begin downloading because someone
  opened the library on cellular.

A setting exposes exactly one control, "download scores over cellular", default
off, and the tiers above are the behaviour behind it. Not four switches.

### 5.3 Offline, and what a person sees

Signed out, there is no Firebase at all: the SDK is configured lazily at first
sign-in, section 9. Signed in and offline:

- Everything held locally reads and edits normally, including running ops, which
  append versions to the local chain exactly as now.
- A shared setlist reads from its local cache. Reordering it, adding to it, or
  changing whose version is pinned is **disabled**, with the reason shown, not a
  silent no-op. Annotating it is **enabled**, because ink is per-user and cannot
  conflict.
- Artifacts not held show as "not downloaded on this device", never as an error
  and never as a blank page.
- There is one status line, not a spinner: "3 changes waiting to sync" and the
  time of the last successful sync. A musician on stage needs to know whether
  what they are looking at is current, and nothing else.

### 5.4 Eviction

An LRU over downloaded artifacts against a budget the user can see, with any
setlist marked offline and any pinned version exempt. Evicting a *local-only*
artifact is never allowed: an artifact that has not yet been pushed is the only
copy that exists. That check is easy to forget and is the sort of thing worth a
test of its own.

---

## 6. Sharing

### 6.1 What a shared setlist is

**An ordered list of pinned arrangement versions, copied at the moment of
sharing, with a per-member ink layer over each.**

Each of those words is load-bearing.

*Pinned versions*, not live scores. An entry names `(scoreUid, versionUid)` and
the version is immutable. Nobody's page reflows mid-gig because the arranger ran
a transpose in the car park, and the annotation problem from section 1.3 stops
being a problem: markup is attached to a thing that cannot change. Moving an
entry to a newer version is an explicit act by an editor, it is visible in the
setlist, and it carries a decision about what happens to the ink (section 6.4).

*Copied*, not referenced into the owner's library. Section 4.3.

*Ordered*, with a fractional index per entry rather than an array on the parent
document. Section 6.5 explains why this is the difference between reordering
working and reordering losing people's work.

*Per-member ink layers*, which is the whole reason this feature exists.

### 6.2 Roles

*Replaced 2026-09-04 by principle 4 (§0.5). The three-role table this section
used to carry, with invitation reserved to the owner, is superseded. The old
reasoning -- that invitation is the act with rights consequences and should have
one accountable person -- is not wrong, and §0.5 says what now carries that
weight instead: the membership cap, enforced in the rules, and a record of who
issued every invitation.*

Two roles issued, three defined:

| Role | Read | Annotate | Add | Reorder | Remove an entry | Invite | Delete the setlist |
|---|---|---|---|---|---|---|---|
| Member | yes | yes | yes | yes | yes | yes | **no** |
| Owner | yes | yes | yes | yes | yes | yes | **yes** |
| Reader *(defined, not issued)* | yes | yes | no | no | no | no | no |

**Every member is an editor.** A band's running order is edited by the band, and
a permission model in which one person is the bottleneck on adding a tune is one
nobody will use. Adding, reordering, removing and repinning are all member acts.

**Only the owner deletes the setlist.** This is the one asymmetry, and it is the
right one: deleting is the only act that destroys other people's work --
everyone's ink, on every entry, at once. It is enforced in the security rules on
`ownerId`, not in the client, and there is no transfer of it except the account
deletion path in §12.6.

**Only the owner removes another member.** Removing a person is the mirror of
deleting the setlist and belongs with the same accountable person. Any member
may remove themselves at any time. Recommended, not dictated by the principle;
§12.9 puts it to the owner.

**Removing an entry is soft.** A member may remove an entry another member
added, because a list anyone can add to and nobody can prune fills with
mistakes. The entry gets `removedAt` and `removedBy`, keeps its ink, and can be
restored. Nothing about a removal destroys bytes.

**Reader is defined and not issued in 0.7.** A dep player who marks their own
part and cannot touch the running order is the first thing a working band will
ask for. The value exists in the `role` field from the start because adding a
value to a field is cheap and introducing the field later is not.

**Every invitation is recorded** -- who issued it, to what address, when -- and
the cap of twelve (§8.2) is enforced in the rules. Under owner-only invitation
the owner was the brake on growth; with member invitation the cap is the only
structural limit left between a band and a distribution list.

### 6.3 Annotation by several people, concretely

*Amended 2026-09-04 by principle 5 (§0.6). The analysis below is unchanged and
still correct. What changed is the verdict it was left open on: **per-participant
layers are the answer, and they ship as part of the headline feature rather than
as a stage after a read-only one.** The band layer stays deferred, and this
section's account of why it is solvable stays here so that a later decision to
build it starts from worked-out ground. One correction to it: it is written as
an editor-role capability, and principle 4 abolishes that distinction, so if the
band layer is ever built every member writes it.*

Two layers per entry per page.

**The personal layer** is one `PKDrawing` per (entry, page, user), owned by that
user, written only by that user's devices, held as a blob field on the
`ink/{userId}` document (section 4.3). There is no conflict to resolve: a user
drawing on two of their own devices at once resolves last-writer-wins, and the
loser is that same person's earlier state, which is what they would expect.
Rendering composites every member's layer that the viewer has switched on, over
the page, in that member's assigned colour when they choose to see whose is
whose.

This is achievable and it is most of the product value. **Ship this before the
shared layer.**

**The band layer** is the hard one, and it is genuinely solvable here because of
one property verified in section 1.3: the eraser is a vector eraser, so an edit
is always *add this whole stroke* or *remove that whole stroke*. Never *change
these pixels*. That makes the layer a two-phase set: a grow-only set of stroke
documents plus a grow-only set of tombstones. Concurrent additions by four
people all survive. Concurrent erasure of the same stroke is idempotent.
Addition and erasure of the same stroke commute to erased. That is a real
conflict-free type, not a hopeful one, and it needs no vector clocks and no
merge function.

Separate documents are also required for a second reason: four people drawing at
once on a single shared blob would be four writers to one document, which is a
last-write-wins collision before it is anything else.

The cost is document count: one Firestore document per stroke, and a busy page
is tens to low hundreds of strokes. The fix is compaction. Each stroke document
carries the serialised single-stroke `PKDrawing` blob; periodically the entry's
owner device folds every live stroke into one compacted blob, writes it, and
tombstones the folded strokes with a compaction marker. A joining device reads
one compacted blob plus whatever arrived since. Steady-state reads are one
document; live editing is one small write per stroke.

**What is honestly out of reach, and should not be attempted:**

- Merging two people's *modifications* to the same stroke. There are none: a
  stroke is created once and deleted once.
- Pixel erasing in the band layer. It would break the model. If the band layer
  ever needs it, the answer is a different feature, not a different merge.
- Cross-user undo. Undo is per-user and reaches only your own strokes, in your
  own layer. An editor who wants to remove someone else's band stroke erases it,
  which is a visible act, not an undo.
- Live cursor and stroke-in-progress streaming. Firestore is not built for it,
  the write rate would be absurd, and nobody needs to watch a stroke being drawn.
  Strokes appear when they are finished.

**Presence** (who else has this setlist open right now) belongs in Realtime
Database rather than Firestore, because `onDisconnect` is what makes presence
correct when someone's iPad goes to sleep mid-set. It is small, it is optional,
and it should be deferred past stage 4 unless the shared layer proves confusing
without it.

### 6.4 Repinning an entry

An editor moves an entry from `v012` to `v019`. Ink is keyed to a version, so
the question is unavoidable and must be answered by design rather than by
accident.

**Recommendation: keep both, show the old, ask once.** The new version arrives
with no ink. Every member whose ink exists on the old version sees a one-line
notice on the entry, "your markup was on an earlier version", with two actions:
look at the old one, or copy my markup across. Copying is a straight blob copy
per page, correct only when the engraving did not reflow, which the app cannot
know. So the copy is offered, the result is shown, and the old ink is never
deleted.

The alternative, refusing to repin while ink exists, protects the markup and
makes the feature useless the first time a wrong note needs fixing. Rejected.

### 6.5 Ordering

The running order is the thing two people are most likely to touch at once, and
an array on the parent document is the shape that guarantees one of them loses
everything. Store `order` as a **fractional index on each entry**: a string or
double between its neighbours, so moving one entry is a one-field write to one
document. Two people moving *different* entries both succeed. Two people moving
the *same* entry conflict, last writer wins, and that is both correct and
unsurprising.

Piece ordering and private setlist ordering inside a library stay as arrays,
because a single library has one authority and no concurrent editors. Do not
generalise the fractional index where it is not needed.

---

### 6.6 Succession: who owns a set list when its owner leaves

Answer 5: *"transfer setlist ownership to the NEXT person who was invited to
that setlist -- ownership passes down the invite order."*

This closes §12.6, which had been open since 2026-08-30 with no good answer. The
alternatives were all worse: a set list with no owner has nobody who can delete
it, deleting it with the account destroys other people's markup, and asking a
departing user to nominate a successor puts a decision in front of somebody who
is in the middle of leaving.

**Invite order becomes stored, ordered data.** Today `invites/{id}` carries
`invitedAt`, and `memberships/{uid}_{setlistId}` carries `joinedAt`. Neither is
the right key:

- `invitedAt` is the order people were ASKED, which is the order the answer
  names -- but invites are deletable and revocable, so the record can vanish
  while the member remains.
- `joinedAt` is the order people ACCEPTED, which is a different order. Somebody
  invited first and slow to accept would be skipped.

So `claimInvite` stamps a **`succession` integer** on the membership document,
taken from the setlist's own monotonic counter and allocated in the same
transaction that admits the member. The owner is 0. It never changes, it never
reuses a number even after somebody leaves, and it survives the invite being
deleted. Ordering by a stored integer rather than by a timestamp also removes
the tie a same-second double-accept would otherwise create.

**A `transferOwnership` Function**, owner-only or triggered by account deletion,
which in one transaction:

1. reads the members and picks the lowest `succession` that is not the current
   owner;
2. sets that member's role to `owner` and the setlist's `ownerId`;
3. demotes the departing owner to `member`, or removes them if they are leaving
   for good.

**And the case the answer does not cover: a set list whose owner is its only
member.** There is nobody to promote. That set list is deleted with the account,
because there is no other person's work in it to protect -- which is the one
place where deleting on account deletion is the right answer rather than the
lazy one.

**Account deletion is a Function and not a client loop.** A client that walked
its own set lists promoting successors would need write access to membership
maps, which is the one thing §4.4 refuses it. It also has to run to completion:
a client killed halfway leaves set lists owned by a deleted account, which is
precisely the state §12.6 was worried about.

*Proves it:* a set list with three members promotes the second-invited when the
owner goes, not the second to accept; a `succession` number is never reused; the
sole-member set list is deleted rather than orphaned; a member cannot call
`transferOwnership`; and the promotion is atomic under a concurrent invite
claim.

## 7. The conflict model

Stated as rules a person could predict, in the order they matter.

**1. Artifacts never conflict.** A version's bytes are immutable and named by an
opaque version ID (section 3). There is no such thing as two versions of a
version.

**2. Two people arranging offline both keep their work.** The version graph
already has `parent`; opaque IDs make a fork representable. Two devices append
to `v012` and produce two children. Both arrive. The arrangement now has a
branch, the app says so once ("Aisha also worked on this while you were
offline"), and both branches are in the version list with their prompts, which
is exactly the affordance the turn-grouped history already provides. The
`latest` pointer resolves to the most recent by timestamp, with the other
branch one tap away.

This is the rule that justifies stage 0. With counted `vNNN` IDs, one of those
two arrangements has to be renumbered or dropped, and neither is explicable to
the person it happens to.

**3. Documents merge field by field, last writer wins per field.** The sync
layer writes `updateData` with only the fields that changed, never `setData`
with the whole document. A rename on one device and a re-file on another are
different fields and both survive. Two renames conflict and the later one wins.
No user-visible notice: the winner is what is on screen, and telling someone
their rename lost is noise.

**4. A delete beats a concurrent edit, and a delete is a tombstone forever.**
`delete_score` already writes `deleted_at` and `sweep()` reclaims after 30
seconds (`UNDO_WINDOW_SECONDS`). Locally that stays exactly as it is. Remotely
the tombstone is **never** swept: the Firestore document keeps `deletedAt` and
loses its fields. Without that, a device that was offline during the delete pushes
the score back up on reconnect, and deleted things returning from the dead is the
single most alarming sync bug a user can meet.

**5. Order merges per entry, not per list.** Section 6.5.

**6. A shared setlist's membership and roles are decided by the server, always.**
There is no offline path that changes who is in a band. An invitation accepted
offline is queued and can fail, and it says so.

**7. The user is told about forks, and nothing else.** A fork creates work that
would otherwise be invisible. A lost rename, a lost reorder and a lost role edit
all leave the winner visible on screen, and announcing them would train people to
dismiss sync notices, which is how they come to dismiss the one that matters.

---

## 8. The rights gate

Treat this as a hard constraint on the design. `.gitignore` already excludes
`workspace/` with the note that it may contain copyrighted scores, and
`BACKLOG.md` records that sharing needs a gate. The library in question is
publisher PDFs, IMSLP scans and a commercial fake book.

The app cannot decide what is lawful. What it can do is make the low-risk act
the default and the high-risk act deliberate, and keep a record of who decided.

### 8.1 The share unit

**Recommendation: the share unit is a setlist entry, and an entry shares as a
*copy* only when the sharer's own arrangement work is in it. Everything else
shares as a *reference*.**

The distinction is computable today from data that already exists. Every version
document carries the `op` that produced it. A chain whose only ops are `import`,
`import-pdf` or `book-extract` is material that arrived from outside. A chain
with at least one arrangement op in it (`transpose`, `keep-parts`,
`change-instrument`, `merge-parts`, `set-chords`, `whistle-fingerings`, and the
rest) contains work the sharer did.

A **copy** entry ships the artifact into `shared/` and everyone reads and
annotates it.

A **reference** entry ships no artifact at all. Members see the title, the
composer, the key, the place in the running order, the page count, and a line
saying the owner has this as a scan and they need their own copy. If a member
happens to have the same piece in their own library, the app offers to attach
theirs to that slot locally, which is what makes a reference entry genuinely
useful rather than a placeholder: the band shares the *set*, and each player
brings their own copy of the music.

Being honest about the limit: transposing a copyrighted song produces a
derivative work, and this gate does not make sharing that lawful. The gate adds
friction where the risk is; a ToS and a real legal review are what determine
what is permitted, and both still have to exist before anyone but the owner uses
this. `ARCHITECTURE.md` already says so and it is still true.

### 8.2 Guard rails

Six, in descending order of how much risk each one removes.

1. **Sharing is to named people, never to a link.** No "anyone with the link"
   mode, in v1 or later. A share is an invitation to an account. This removes
   the entire category of accidental public redistribution, which is the only
   category that turns into a takedown.
2. **A shared setlist has a membership cap.** Twelve. A band, a section, a
   school ensemble is smaller; the cap is not a limit anyone reaches
   legitimately, and it makes "distribution" hard to arrive at by accident.
   Enforced in the security rules, not in the client.
3. **Books never share.** No affordance on a book, anywhere. `create_book` is
   the only way one enters the library, so this is one rule in one place. A fake
   book is the clearest redistribution risk in the whole product and there is no
   legitimate in-app reason to send one to another user.
4. **Sources never share.** Sources are other people's editions, imported for
   reference. Same reasoning, same enforcement.
5. **Copy mode on an all-import chain requires an explicit acknowledgement, and
   the acknowledgement is recorded.** There will be cases where a copy really is
   fine (public domain, the sharer's own scan of their own composition, a piece
   the whole band has bought). The escape hatch exists, it is per entry, it
   names the people it will reach, and it writes `rightsAcknowledged` with the
   sharer's user ID, the entry, and the timestamp. The record is the point: it
   makes a takedown answerable and it makes the decision feel like one.
6. **Nothing leaves the device without an account and an explicit act.** Signed
   out, the app is what it is today, byte for byte.

### 8.3 The question this design does not answer

Backing up the owner's *own* library to their *own* Cloud Storage bucket puts a
copy of a commercial fake book on a service operator's servers. That is a
different posture from the same file sitting on their iPad, even though nobody
else can read it. `ARCHITECTURE.md` cites Soundslice and Newzik as operating
private user-scoped storage of uploaded publisher PDFs, which is the industry
posture and is defensible. This design follows it, and makes book backup opt-in
per book (section 5.1) so the owner is choosing rather than discovering. Whether
that is enough is a question for a lawyer, not for me, and it should be answered
before stage 1 ships to anyone outside the household.

---

## 9. Auth without an account wall

### 9.1 The pre-account state is no Firebase at all

**Recommendation: do not use anonymous auth as the signed-out state. Do not
configure the Firebase SDK until the user signs in.**

Anonymous auth is the conventional answer and it is wrong here. It creates a
server-side identity for a person who declined to have one, it puts a network
round trip in first launch, it leaves an orphan account behind for everyone who
tries the app once, and it buys a linking step that this design does not need.
The app already works with no account, no network and no Google contact, and
that property is worth keeping literally rather than approximately.

The trade-off, stated: App Check on the OMR service can only cover signed-in
users, so signed-out OMR keeps the current baked-key posture until someone
abuses it. That is acceptable while OMR is one Cloud Run instance with
`--max-instances 1`. If abuse becomes real, the right response is to require
sign-in *for OMR*, not to require an identity for launching the app. Open
question 12.4.

### 9.2 Adoption, not migration

The local library gets a `libraryId` (a ULID) on first launch, written into the
database before any account exists. Every document already has a `uid` from
stage 0. Signing in therefore does not *migrate* anything: it writes
`libraries/{libraryId}.owner = auth.uid` and starts pushing. There is no "would
you like to upload your existing data" dialog, because there is nothing to
convert. The library already had an identity; signing in gave it an owner.

*Amended 2026-09-04 by principle 3 (§0.4). The recommendation this paragraph
made -- Sign in with Apple alone -- is overturned. The research behind it is not,
and it is what makes the cost of the new decision knowable in advance.*

Sign-in is **Google SSO, with Sign in with Apple offered beside it.** Google is
the primary method because the people this product shares with are bands, and an
invitation addressed to a Google account is addressed to the address they
already use.

Sign in with Apple ships too, and it is not optional: App Store Review Guideline
4.8 obliges an equivalent privacy-preserving option once a third-party or social
login is offered, and Sign in with Apple is the cheapest way to satisfy it --
no password handling, no email verification of our own. Shipping Google alone
is not a choice that is available.

Both methods land on one Firebase Auth user record. A user who signs in with
Google and later with Apple, from the same device, must not end up with two
libraries; Firebase's account linking covers this and the flow needs to be
exercised rather than assumed.

The one thing Sign in with Apple costs this design: Hide My Email, which the
superseded recommendation counted as an advantage, hands us a private relay
address, and a member who signs in that way cannot be found by the address their
bandmates know them by. Invitation has to handle it. §12.10.

Signing out keeps everything local and stops the sync layer. It does not delete
the library, and it says so.

### 9.3 The messy corner

Two iPads, each with a local library built up separately, both sign into the
same account. There is no correct automatic answer: the union is wrong (two
copies of every piece the owner imported twice), and picking one is data loss.

**Recommendation: an account owns a *set* of libraries.** Both appear, named by
the device they came from, and the app offers to move arrangements from one to
the other, per arrangement, with duplicates flagged by title. It is a screen
somebody has to design and it will be used approximately twice per user, which
is exactly the sort of thing that gets skipped and then bites. Budget for it in
stage 1 rather than discovering it in stage 1.

---

## 10. Firebase specifics this design relies on

Read from Firebase's documentation on 2026-08-30. Each claim carries its source.
The unverified ones are marked and turned into questions in section 12.

### 10.1 Verified, and load-bearing

**Storage rules can read Firestore, but only two documents per evaluation.**
`firestore.get()` and `firestore.exists()` are available in Cloud Storage
security rules, against the default database only, billed against the Firestore
quota, with a hard cap of **two Firestore document accesses in a single rules
evaluation**.
([rules-conditions](https://firebase.google.com/docs/storage/security/rules-conditions))

This is the answer to the question the design most needed, and it is a yes with
a shape attached. A member's read of `shared/{setlistId}/{entryId}/…` is
authorised by exactly one lookup:

```
match /shared/{setlistId}/{rest=**} {
  allow read: if request.auth != null &&
    firestore.get(/databases/(default)/documents/setlists/$(setlistId))
      .data.members[request.auth.uid] != null;
}
```

One document, well inside the cap, and the `setlistId` comes out of the path
rather than out of a traversal. **This is why `shared/` is keyed by setlist and
why membership is a map on the setlist document rather than a subcollection.**
If membership were a subcollection, or if the artifact path did not carry the
setlist ID, the rule would need a traversal it is not allowed to do, and the
whole thing would fall back to a Cloud Function minting signed URLs. The layout
in section 4.3 is chosen for this rule.

Custom auth claims (`request.auth.token`) are the cheaper alternative because
they cost no billed read, but they are capped at 1000 bytes and have to be
re-minted by a Cloud Function on every membership change, with a token refresh
before the client sees them. Not worth it at this scale. Revisit if the billed
read per artifact download ever shows up on a bill.

**Listener resync after 30 minutes offline is billed as a fresh query.** With
persistence enabled, a listener disconnected for more than 30 minutes is charged
for every document and index entry as though a brand-new query had been issued.
Without persistence, that charge lands on every reconnect.
([pricing](https://firebase.google.com/docs/firestore/pricing))

For an app whose defining property is being offline, this is the dominant cost
variable, and it rewrites part of section 5.1: **do not hold a long-lived
listener on the library.** Section 5.1 has been written against this.

**Firestore document limits.** 1 MiB per document, 1 MiB minus 89 bytes per
field value. ([quotas](https://firebase.google.com/docs/firestore/quotas)) A
compacted ink blob has to stay under that, which needs a measured check rather
than an assumption (stage 3's proof).

**Transactions fail offline; batched writes do not.** A Firestore transaction
requires connectivity. A batched write executes offline and is queued.
([transactions](https://firebase.google.com/docs/firestore/manage-data/transactions))
Nothing on the local library path uses a transaction. Membership changes and
quota increments do, and both are server-side, which is consistent with rule 6
in section 7.

**Rules are not filters.** A query is all or nothing: Firestore evaluates it
against its potential result set, so the query must carry the same constraint
the rule enforces or the whole request fails.
([rules-query](https://firebase.google.com/docs/firestore/security/rules-query))
This is why `memberships/` exists as a flat collection keyed on the user: "what
setlists am I in" has to be a query the rules can approve on its face.

**Firestore rule lookups are capped and billed.** 10 `get()`/`exists()` calls
for a single-document or query request, 20 for multi-document reads and batched
writes, and the reads are billed *even when the rule rejects the request*.
([rules-conditions](https://firebase.google.com/docs/firestore/security/rules-conditions))
Every rule in this design is one lookup or none.

**Offline persistence on Apple platforms.** On by default; the current API is
`FirestoreSettings.cacheSettings` with `PersistentCacheSettings`, replacing the
deprecated `isPersistenceEnabled`. Default cache threshold 100 MB, minimum 1 MB,
`FirestoreCacheSizeUnlimited` available. The cache holds only documents the app
has actually read, so data must be read online once to be available offline.
Offline conflict resolution on a single document is last-write-wins.
([enable-offline](https://firebase.google.com/docs/firestore/manage-data/enable-offline))

**Offline query indexing is off by default.** Long offline periods degrade query
performance unless `indexManager.enableIndexAutoCreation()` is called, and it
must be called on **each app start**.
([enable-offline](https://cloud.google.com/firestore/native/docs/manage-data/enable-offline))
One line in `ScorangerApp`, easy to omit, and the symptom is slow rather than
broken, which is how it stays omitted for a year.

**App Check does not natively enforce on Cloud Run.** The enforceable list is
Firestore, Realtime Database, Storage, Auth, and *callable* Cloud Functions.
A Cloud Run service is a "custom backend": the client sends the App Check token
and the service verifies it with the Admin SDK itself.
([enforcement](https://firebase.google.com/docs/app-check/enable-enforcement),
[custom backend](https://firebase.google.com/docs/app-check/custom-resource-backend))
So the OMR change in stage 1 is real server work in `omr-service/server.py`, not
a console toggle. Apple attestation is App Attest on iOS 14+ with DeviceCheck as
the fallback, and **App Attest sandbox tokens are rejected**, so the simulator
and CI need the debug provider.
([app-attest](https://firebase.google.com/docs/app-check/ios/app-attest-provider))

**Cloud Storage: 5 TiB per object, one write per second per object name.**
([quotas](https://docs.cloud.google.com/storage/quotas)) The per-object write
rate binds the ink design: one blob per (user, page) is fine, one blob per page
shared by four people would not be, which is a second reason section 6.3 splits
strokes into documents.

**Blaze is required, and the free allowance is per-operation as well as
per-byte.** Cloud Storage for Firebase requires the pay-as-you-go plan for all
buckets including the default one, in effect since 3 February 2026. New
`firebasestorage.app` buckets carry a no-cost allowance of 5 GB stored, 100 GB
downloaded per month, **5,000 uploads per month** and 50,000 downloads.
([storage changes](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024),
[pricing](https://firebase.google.com/pricing))

The upload count is the one to watch, not the bytes: every arrangement op
produces a version, and a heavy arranging session is dozens of uploads. A
household will not reach 5,000 a month. A dozen active users might. Budget for a
small real bill from day one of stage 1.

**No merge primitives anywhere in Firebase.** Nothing CRDT- or OT-shaped;
Firestore's stated conflict model is last-write-wins per document.
`arrayUnion()` and `arrayRemove()` are server-side transforms, so concurrent
adds from different clients do all land, which is a genuinely useful primitive
and still not a merge strategy for a drawing. Section 6.3 builds its own out of
the one property that makes it possible.
([add-data](https://firebase.google.com/docs/firestore/manage-data/add-data))

### 10.1.1 Cross-service rules need an IAM grant the CLI would have made

**Found in Ali's hands on 0.7.3 build 187, 2026-09-10.** The owner shared a set
list and every upload to `shared/{setlistId}/…` came back *"User does not have
permission to access gs://scoranger.firebasestorage.app/shared/…"*. The rules
live were byte-identical to `firebase/storage.rules`; the set list document
existed with the owner in `members`; the `memberships` row existed.

The Storage rule reads the members map with `firestore.get`. Live, that read is
made by the Storage service agent
(`service-<project-number>@gcp-sa-firebasestorage.iam.gserviceaccount.com`),
and it needs `roles/firebaserules.firestoreServiceAgent` on the project. The
Firebase CLI grants it when it deploys Storage rules that use `firestore.*`;
ours were released through `firebaserules.googleapis.com` directly, so no grant
was made, the read failed, and an evaluation error is a deny.

**The emulator does not need the grant**, so §10.1's 44 rules assertions were
green throughout and could not have caught it. This is the class of thing only
the live project can answer, so `deploy_testflight.sh` now asks the live
project: a Firebase-linked archive is refused unless the binding exists.

### 10.2 Not verified, and what the design does about it

**Whether Firestore's pending-write queue survives app termination is not
documented.** The explicit "queue is persisted to disk" wording belongs to
Realtime Database, not Firestore. `waitForPendingWrites()` is documented as
covering writes from a previous app session, which implies persistence without
stating it.

*What the design does:* nothing changes, because the change journal in section
4.1 is already the durable record of what this device owes the server, and the
push loop re-drives from it on launch. Firestore's queue surviving is a
performance detail, not a correctness dependency. Worth an empirical check
during stage 1 all the same.

**Cloud Storage uploads almost certainly do not survive app termination.** The
iOS SDK exposes no resumable session URI, and backgrounding gives roughly the
standard 30-second background task window. Verified only from SDK issue threads,
not from documentation.

*What the design does:* the artifact upload queue is the app's own, persisted,
and re-drives an interrupted upload from the start on next launch. `pause`,
`resume` and `cancel` on `StorageUploadTask`
([upload-files](https://firebase.google.com/docs/storage/ios/upload-files)) are
used within a session only. A first sync of a 52 MB book is therefore chunked
into whatever the session survives and re-attempted, which is another reason
books do not sync by default.

**Cloud Storage has no offline queue at all.** No documented queueing; the
"restarts where it stopped" language covers a network interruption during a live
task. Assumed correct, and the design already owns its own queue.

**The 500-writes-per-batch limit is folklore.** It is not in the current quotas
page; what is documented is a 10 MiB request cap and 500 *field transformations*
per document per commit. Design to the request size, not to a document count.

**A per-client listener cap of 100 is not documented.** Widely repeated, not
found in the quotas. Not designed against as a hard number, and section 5.1's
listener discipline keeps the count in single digits anyway.

**Apple's guideline 4.8 bites only if a third-party or social login is
offered.** An app that ships Sign in with Apple alone, or its own accounts
alone, is not caught by it.
([App Store guidelines](https://developer.apple.com/app-store/review/guidelines/))
Section 9.2's recommendation of Sign in with Apple only is therefore the simple
path, and adding Google Sign-In later is what would create the obligation, not
what would satisfy it.

**Anonymous accounts older than 30 days are deleted automatically**, but only
when Identity Platform's clean-up is enabled; linking an anonymous account to a
sign-in method exempts it, and linking preserves the UID so uid-keyed paths
survive.
([anonymous-auth](https://firebase.google.com/docs/auth/ios/anonymous-auth))
Recorded because it is the strongest technical argument for section 9.1's
recommendation against using anonymous auth as the signed-out state: an identity
that silently expires is worse than no identity.

---

## 11. Execution plan

*Rewritten 2026-09-04 by principle 2 (§0.3). The five-stage plan this section
carried reached the goal at stage 2 of 5, after a full multi-device library sync
that the shared setlist does not depend on. The stages themselves were
well-chosen and most of their content survives; what changed is the order, and
the finding behind the reorder is in §0.3. Stage 0's record of what was built is
kept verbatim at §11.0 because it is history, not plan.*

Seven increments, each a TestFlight build, each leaving the app in a state worth
having, each with something that fails without it. The current release is 0.6.9,
build 168.

**The shape of the sequence:** everything that can be done without a Firebase
project is done first, on purpose. 0.7.0 and 0.7.1 touch no cloud at all and
deliver a real sharing feature. Only at 0.7.2 does anything need a project to
exist, and only at 0.7.3 does anything need a deployed function or a bill.

| | What ships | Needs a Firebase project | Needs a deploy |
|---|---|---|---|
| 0.7.0 | stable identity on current `dev` | no | no |
| 0.7.1 | share by AirDrop | no | no |
| 0.7.2 | sign in, and nothing else changes | **yes** | no |
| 0.7.3 | a shared setlist you can open | yes | **rules, maybe a function** |
| 0.7.4 | everyone adds and reorders | yes | rules |
| 0.7.5 | everyone's markup | yes | rules |
| 0.7.6 | your own library on your other iPad | yes | rules |

### 11.0 Stage 0: stable identity -- BUILT, and not yet on `dev`

Built on `feat/firebase`, whose base is 191 commits behind `dev` as of
2026-09-04. Re-landing it is 0.7.0. The record of what it built and what it
deliberately built differently is unchanged below, at the old §11 stage 0.

### 11.1 -- 0.7.0 Stable identity, on current `dev`

**Nothing user-visible.** Re-land the `feat/firebase` groundwork onto current
`dev`, and finish the one deferral that now has a consumer.

- Merge `feat/firebase` into a branch off `dev`. Measured with
  `git merge-tree`: **five conflicting files** -- `.gitignore`, `CLAUDE.md`,
  `AppState.swift`, `ManagementScreens.swift`, `ScoreScreens.swift`. The two
  largest overlaps, `workspace.py` and `ScorePagesView.swift`, auto-merge, as do
  `cli.py` and `bridge.py`. This is a day, not a week, and the check suite is
  what confirms it.
- **Re-key annotations to `(scoreUid, versionUid)`.** Stage 0 deferred this,
  correctly, because it bought nothing until sync existed. §13.3 gives it a
  consumer that is not sync: a bundle cannot carry ink keyed by a slug, because
  the receiving device's slug is its own. `DrawingStore.migrateVersionKeys` is
  the precedent.
- **Write `libraryId` into the database on first launch** (§9.2). A ULID, before
  any account exists, so that signing in later is adoption rather than migration.
- Rename `check_sync.py`'s signed-out assertions into `check_signed_out.py` and
  make it a release gate (§0.2).

*Proves it:* `check_identity.py`, `check_signed_out.py`, and the full existing
suite green, including `check_workflows.py` and `check_undo.py` which are what
catch a bad re-key.

*Risk:* the merge is the whole increment and it is boring. The failure mode is a
half-landed identity change, which is why nothing else ships in this build.

### 11.2 -- 0.7.1 Share by AirDrop

Section 13, entire. `bundle-export`, `bundle-inspect`, `bundle-import` in the
engine; the UTI and `onOpenURL` in the app; the import screen; export rows on an
arrangement and on a setlist, going out through the existing `SystemShareSheet`.

**What the user can do that they could not:** hand a bandmate an arrangement or
a whole setlist, with their markup, over AirDrop. **What is absent:** any
account, any network, any Firebase.

*Proves it:* `check_bundle.py` (§13.4) -- round-trip into a fresh workspace,
artifacts byte-identical, ink on the right page of the right version, no export
path for a book or a source, double import produces two arrangements. Plus one
manual device-to-device AirDrop, because a UTI registration is not testable in
the engine.

*The reason to ship this first:* it is the only increment that is pure gain
under principle 1, it is the whole of principle 6, and it writes down the
payload that 0.7.3 then also carries (§0.7).

### 11.3 -- 0.7.2 Sign in, and nothing else changes

Firebase Auth with **Google SSO and Sign in with Apple** (§9.2, §0.4). An
account screen. Account linking when the same person uses both. App Check on
Auth. `FirebaseApp.configure()` at first sign-in, never at launch.

**Nothing syncs.** No library mirror, no sharing, no listeners, no Storage. The
build's entire user-visible content is that you can sign in, see who you are
signed in as, and sign out, and that signing out changes nothing about your
library.

**This is the build where the local-first invariant is proved**, because it is
the first build where it could break. §0.2's UI test walks every screen signed
out; `check_signed_out.py` asserts the engine half.

*Proves it:* the two checks above, plus an instrumented assertion that no
Firebase network call occurs on a signed-out launch. That last one is the
guarantee, and asserting it in code is the difference between a principle and an
intention.

*Needs from the owner:* a Firebase project. Nothing is deployed to it in this
build -- Auth is configuration, not a deploy -- but the project has to exist and
it is Ali's Google account that owns it. **Explicit go-ahead required (§0.9).**

*The reason to ship this alone:* an auth integration that ships with a feature
attached is an auth integration whose bugs are attributed to the feature.

### 11.4 -- 0.7.3 A shared setlist you can open

Top-level shared setlists (§4.2), invitation by email address (§4.2 `invites/`),
membership and the cap of twelve, the `shared/` Storage prefix and its
one-lookup authorisation (§4.3, §10.1), and **the rights gate in full** (§8):
reference versus copy, the acknowledgement record, the book and source bans.

**The owner of a setlist adds entries and invites people. Members read.** Adding
and reordering by members is 0.7.4; annotation is 0.7.5. Splitting it this way
is the old plan's stage 2 reasoning and it survives the reorder intact: this
build exercises membership, rules, cross-user artifact authorisation and the
rights gate -- the parts most likely to be wrong -- with no concurrency in it.

*Proves it:* rules tests for every role and every collection including the
negatives (a non-member reads neither the setlist, nor its entries, nor anything
under its `shared/` prefix); a test that a book and a source have no share path;
a test that a reference entry ships no bytes; a test that an unaccepted invite
grants no read.

*Also lands here, and it is not optional:* the OMR service moves off the baked
header key to a verified Firebase ID token with a per-user monthly page cap
enforced in `omr-service/server.py` (§1.4, §10.1). App Check has no native Cloud
Run enforcement, so the service verifies both tokens with the Admin SDK itself.
This is the first build with more than one account in it, and a shared key with
no attribution stops being a prototype posture at that moment.

*Gated on, and this is a stop condition not a caveat:* §12.8. A terms of service
must exist and the rights gate must have been read by someone who is not an
engineer before this build reaches anyone outside the household. The code can be
written; it cannot ship to a band without that.

### 11.5 -- 0.7.4 Everyone adds and reorders

Principle 2 and principle 4, complete. Members add entries, reorder by
fractional index (§6.5), remove softly (§6.2), repin (§6.4), and invite (§4.2).
The owner alone deletes the setlist and removes other members. The fork notice
from §7 rule 2.

**What the user can do:** the running order is the band's, editable by the band,
live.

*Proves it:* two editors move different entries concurrently and both moves
survive; two editors move the same entry and the later wins with no third state;
a member cannot delete the setlist and a rules test says so; the cap is enforced
in the rules and a thirteenth invitation fails server-side; an offline reorder
is refused with a reason shown rather than silently lost (§5.3).

### 11.6 -- 0.7.5 Everyone's markup

Principle 5, complete. Per-participant ink layers, synced (§6.3, §0.6). The
visibility control: mine, everyone's, or one person's, defaulting to everyone's.
Per-participant colour. The repin flow of §6.4.

**What the user can do:** the whole product ask. Everyone's cues, on the same
running order, in sync, on everyone's device.

*Proves it:* a rules test that a member writes only their own `ink/{userId}` and
no other member's; a member's ink survives a repin and is still reachable; and
**a measured check that a real dense page of markup fits well inside Firestore's
1 MiB document limit**, which is currently an assumption and needs to stop being
one before this ships.

### 11.7 -- 0.7.6 Your own library on your other iPad

The old stage 1, minus what has already landed. `SyncCoordinator`; the library
mirror driven by the change journal; artifact sync with the holding policy and
gzip; the pull query rather than a listener (§5.1); eviction (§5.4); the
two-libraries screen (§9.3); App Check on Firestore and Storage.

Much of the offline half of this is already written and tested on
`feat/firebase`: `JournalingRepository`, `VersionGraph.swift`, `SyncMerge.swift`,
`ArtifactHolding.swift`. What is left is the coordinator, the Firebase wiring
and the two-libraries screen.

**Why last rather than first:** §0.3. **What it costs to have it last:** a lost
or replaced iPad is unprotected until this ships, and the bundle export of 0.7.1
is a manual answer rather than a backup. That is the honest price of the
reorder and the owner should hear it in those words.

### Deferred past 0.7

The band layer (§6.3, §0.6), presence, page-follow, public links (recommended
never), a web client, and the hosted agent loop from `ARCHITECTURE.md`.

### 11.9 What 0.7.0 actually shipped, and what it does not

Written after the fact, against the code, because §11.3 to §11.6 were planned
as four TestFlight builds and the owner asked for one: *"build all of these
necessary features for sharing playlists into the first 7.0 build."* So 0.7.0
is the whole of 0.7.2 through 0.7.5 and this records where that leaves things.

**Built and enforced.** The Firebase project, billing, Firestore, Storage and
Auth (Google and Apple). The security rules, deployed and verified
byte-identical against what is in `firebase/firestore.rules` and
`firebase/storage.rules`, with 44 emulator assertions behind them
(`firebase/rules.test.mjs`, `engine/scripts/check_rules.py`). `claimInvite` and
`removeMember`, deployed and ACTIVE in `us-west1`, which are the only writes to
a membership map that exist. The cap of twelve, enforced transactionally in the
Function and again in the rules so it cannot be side-stepped at creation.

**Built, and verifiable only with two accounts on two devices.** Everything in
`ios/Scoranger/Account/`: creating a shared set list, adding an entry as a copy
under `shared/{setlistId}/{entryId}/`, reordering by fractional index,
inviting, claiming by link, per-participant ink in both directions, and reading
an entry by importing this device's copy. Every DECISION these make is tested
locally and every RULE they will meet is tested against the emulator; that the
calls themselves succeed is not, and cannot be, without the owner's
credentials. This is stated plainly rather than counted as done.

**Deliberately not built, and the owner should know it was a choice.**

- **The OMR service still uses the baked header key.** §11.4 called moving it
  to a verified Firebase ID token with a per-user page cap "not optional", and
  that judgement stands for a band: a shared key with no attribution is not a
  posture to keep once more than one account exists. It is not a sharing
  feature, it is a separate Cloud Run service, and it does not gate anything in
  this build -- so it was left, said out loud, rather than half-done in the
  same night as the sharing work. **It is the first thing 0.7.1 should do.**
- **The continuous strip draws no shared ink, because it draws no ink at all.**
  `PencilCanvas` appears in exactly one place in `ScorePagesView.swift` -- the
  paged `PageView` -- so continuous mode has never had an annotation canvas,
  and the shared overlay inherits that rather than introducing it. Worth
  recording as one gap and not two: whoever gives the strip a canvas should
  give it the overlay in the same change, and until then a reader who marks up
  in paged mode and reads in continuous sees nobody's marks including their
  own. Not a 0.7 regression.
- **Presence, page-follow and the band layer** stay where §0.6 and the list
  above put them.

**The stop condition of §12.8 has not been met and is not met by this build.**
A terms of service does not exist and the rights gate has not been read by
anyone who is not an engineer. The owner settled the copyright posture for his
own use -- *"what I have is mine and i've purchased them. They should not be
shared with everyone who gets the app; i'll share it with my son for playing
together using shared playlists"* -- and the design answers exactly that: named
people only, capped at twelve, no public link at any path, and books and
sources refused a share path outright. **That covers a household. It does not
cover a band, and it does not cover strangers.** Before this reaches anybody
outside the household, §12.8 is a gate and not a caveat.

### 11.10 Re-sequenced for the six answers, 2026-09-08

§11.1-§11.7 were written before the answers and §11.9 records what 0.7.0
actually built. This replaces the plan from here on. It is ordered by what
BLOCKS what, not by size.

**Two things gate every 0.7 build, and neither is negotiable.** They are listed
first because they are release blockers, not work items.

| # | Blocker | State |
|---|---|---|
| B1 | **No score bundled in a Release build.** Answer 1. | **FIXED** (§0.11), gated by `check_no_bundled_scores.py`, proven with a Release build. Build 180 still carries them and must not reach an external tester or App Review |
| B2 | **The 0.6.x line is fully clear.** Standing rule. | **NOT CLEAR.** 0.6.20 build 180 is VALID on TestFlight, but `PaginationAfterAnOp.testTheSystemCountAgreesWithTheEngine` fails 3/3 run alone and PASSED in the sharded gate on a different pagination -- a test-isolation defect, so its green is not evidence either way (`BACKLOG.md`). 0.6.x is not clear while a release gate can pass for the wrong reason |
| B3 | **The deploy preflight works.** | **FIXED.** It scraped the vendored module list out of `vendor_engine.sh` with a `sed` that stopped matching when that script began deriving the closure, so every deploy died reading its own input. Now calls `check_vendored_engine.py`. Verified both directions |

#### 0.7.1 -- The rights posture, and the things that block shipping

Everything above, plus what answer 1 implies beyond the bundle:

- **The <12 cap**, at TWELVE including the owner, in the client and in
  `claimInvite`, with the test that reads the server's number so the two cannot
  drift (§0.10). **Done, and no redeploy needed** -- the deployed Function
  already enforced 12, which is what the confirmed intent turned out to be.
- **Per-user OMR attribution** (§0.12): the verified-token path, the actor on
  every job, and the structured usage line. Done in code. **Not deployed** --
  it needs a `--update-env-vars FIREBASE_PROJECT_ID` on the service first, and
  both are live infrastructure and therefore the owner's call.
- **§12.8's stop condition.** A terms of service, and the rights gate read by
  somebody who is not an engineer. Answer 1 is the posture the ToS states, so
  this is now writable where before it was blocked on the posture.
- Trim music21's 274 KB of test fixtures from the bundle (§0.11). Hygiene.

*Why first:* B1, B2 and the cap are the only items in the whole line that can
make a build wrong rather than incomplete.

#### 0.7.2 -- QR, and joining with no internet

Answer 3, the half that does not exist. §13.6.

- The invite URL as a **QR code**, and a camera path that reads one. No new
  server work: a QR is the URL.
- **The offline join:** a `.scorbundle` carrying a set list plus a queued
  `inviteId`; content immediately, membership when the network returns; and the
  reconciliation that stops a later claim producing a second copy.
- The three-button share sheet that names each consequence.

*Why here:* it is principle 6, it needs no schema change, and it is the only
part of the sharing story a person can use in a room with no signal.

#### 0.7.3 -- Succession

Answer 5. §6.6.

- A `succession` integer allocated in `claimInvite`'s transaction; owner 0,
  never reused, independent of the deletable invite record.
- A `transferOwnership` Function, and account deletion that walks the owner's
  set lists server-side.
- The sole-member set list deleted with the account rather than orphaned.

*Why after 0.7.2:* it is the only remaining item that changes the schema, and it
is easier to add a field before there is a second device's data to migrate than
after.

#### 0.7.4 -- Your own library on your other iPad

Answer 6, moved into the line from §11.7.

- The `JournalingRepository` installed on sign-in, `VersionGraph`/`SyncMerge`/
  `HoldingPolicy` wired to real documents, artifacts to Storage under
  `libraries/{libraryId}/`.
- The 24:1 compression measurement of §1 is what makes this affordable and it
  should be re-measured against a real library before it ships.

*Why last:* it is the largest piece, it is the one the owner deprioritised in
answer 2's re-sequencing and has now asked back into 0.7, and **it is the only
increment that can lose data.** Sharing writes copies; this writes the library
itself. It goes last so it is never the thing being debugged at the same time as
something else.

#### What answer 2 changed: nothing

*"Only the owner can remove MEMBERS. ANY member can remove PIECES/entries."*
Already the implemented model and already enforced:
`SetlistPermission.membersMayRemoveEntries = true`,
`membersMayRemoveMembers = false`, `.deleteSetlist` a literal `false` for
members, and the rules and `removeMember` agreeing. §12.9 closes with no code
change. Recorded because "no change needed" is a result.

#### Still deferred past 0.7

The band layer (§6.3, §0.6), presence, page-follow, public links (recommended
never), a web client, the hosted agent loop, and shared ink in the continuous
strip -- which draws no ink at all today and inherits that (§11.9).

### 11.8 What must not be done before the owner says so

Recorded here because the sequence above is a plan and not a licence:

- No Firebase project is created. 0.7.2 needs one and it is Ali's account.
- No security rules, Cloud Function or configuration is deployed to any project.
- No change to `omr-service` deployment.
- Nothing is pushed to a remote that carries a project ID, a bucket name or a
  `GoogleService-Info.plist`. That file is gitignored and the build copies it
  in, the way the OMR key is read today.

  **Amended 2026-09-08, by measurement.** The reversed client ID *is*
  committed, in `project.yml`'s `CFBundleURLTypes`. Google's sign-in flow
  returns through a custom URL scheme and the scheme must be in the STATIC
  Info.plist: Xcode regenerates the built one after post-build scripts run, so
  a scheme injected there disappears with no error and the browser opens for
  sign-in and never comes back. That was tried first and measured failing.
  A reversed client ID is a public OAuth client identifier, in plain text
  inside every copy of every app that uses Google sign-in, and it grants
  nothing by itself. The API key and the rest of the plist stay out, and what
  protects the data is the security rules.

0.7.0 and 0.7.1 clear this bar entirely: neither touches a cloud service.

---

### The superseded five-stage plan, kept for its stage 0 record

*Everything from here to section 12 is the 2026-08-30 plan. Stage 0's account of
what was built and why it differs from its own design is history and is the
reason it is kept. Stages 1 to 4 are superseded by §11.1 to §11.7 above; their
content largely survives the reorder and is worth reading for the detail the
rewrite compresses.*

### Stage 0: stable identity — BUILT

**Nothing user-visible ships.** Every score, piece, setlist, book and source
gets a ULID `uid` (`engine/scoranger_engine/ids.py`); version keys became opaque
with `vNNN` demoted to a `label` on the document; `db.py` gained a `Repository`
protocol and `workspace._repo()` a `repository_factory`. The
`FirestoreRepository` promise in `db.py`'s module docstring and in `CLAUDE.md`
is replaced with a pointer to this document, because a stale plan in the file
every contributor reads first is worse than no plan (section 1.1).

*Proves it:* `check_identity.py`, plus the existing suite green.

**What was built differently from this section's original plan, and why:**

- **The slug stays the local primary key.** `uid` is additive. `rename_slug`
  keeps doing exactly what it does locally and is simply invisible to sync,
  which is what section 3's table always said.
- **The annotation key stays `<slug>/<versionId>`**, not
  `<scoreUid>/<versionUid>`. `DrawingStore.rename` already handles slug moves,
  so switching to the uid buys nothing until sync exists and risks a reader's
  markup now. Stage-1 work. `DrawingStore.migrateVersionKeys` re-files markup
  from the old `vNNN` onto the opaque id, driven by the manifest.
- **The `changes` journal and `rev`/`synced_rev` were NOT built.** They have no
  consumer until the sync layer exists, and unused schema goes stale before it
  is used. The injection point is the part that mattered; adding them later is
  a one-file change.
- **Existing artifacts never move.** A version document already carried its
  filename in `file` independently of its id, so the whole migration is
  database-only. A migration that renames nothing cannot half-rename anything.

**Known latent issue, accepted:** accessibility identifiers key on the *label*
(`menu-version-v001`, `version-<slug>-v001`) rather than the opaque id, which is
what keeps the UI tests readable and passing. Two forked versions share a label,
so they would share an identifier. Harmless until stage 4 makes forks reachable;
fix it there by keying identifiers on the id and updating the UI tests together.

**Ordering, settled by test:** stage 0 can ship *after* a large import. A
library built by the pre-stage-0 engine (43 arrangements, 104 versions, 111
artifacts, including PDF arrangements, a book with extractions, sources, a
setlist and a soft-deleted score) migrates in ~120 ms with every artifact
byte-identical; subsequent launches cost nothing. There is no release-sequence
constraint in that direction.

The direction that *does* bite is a **downgrade**: an engine rolled back to
before stage 0 appends a version keyed `vNNN` into an already-migrated
arrangement. The migration's fast skip is therefore conditioned on the score's
`uid` *and* on `latest` looking like an id, since any version an old engine
writes becomes `latest`. Without that second condition the stray version is
skipped for ever, and a second one would collide with it and overwrite. Covered
by `check_identity.py`.

### Stage 1: sign in, and your library is on your other iPad

Firebase Auth with Sign in with Apple; `SyncCoordinator` in Swift; user-scoped
Firestore documents; artifact sync with the holding policy and gzip; the two
libraries screen from section 9.3; App Check on Firestore and Storage; and the
OMR service switched from the baked header key to a verified Firebase ID token
with a per-user monthly page cap enforced server-side.

The OMR change is more work than it sounds. App Check has no native enforcement
for Cloud Run (section 10.1), so `omr-service/server.py` verifies both the ID
token and the App Check token itself with the Admin SDK, and the quota counter
is incremented there rather than by the client. The App Attest sandbox is
rejected, so the simulator and CI need the debug provider wired up, which is the
sort of detail that stops a build working on someone else's machine.

**What the user can do that they could not:** open the same library on a second
iPad, and on an iPhone. **What is absent from the UI entirely:** sharing. No
disabled third tab lit up, no "coming soon".

*Proves it:* an emulator-backed integration test that runs two simulated devices
through import, arrange, delete and rename, offline and online, and asserts they
converge; a rules test suite (`@firebase/rules-unit-testing`) asserting no user
can read another's library; and a test that an unpushed artifact is never
evicted.

*The reason to ship this alone:* it is the whole sync spine under load, with
exactly one user's data at stake and no concurrency. Every bug found here is a
bug not found in front of a band.

**Built so far, all of it offline and none of it touching Firebase.** The parts
of stage 1 that can be decided without a project were done first, on purpose:
they are the parts a live backend makes slow and expensive to get wrong, and
they are testable in three seconds without one.

- `engine/scoranger_engine/sync.py` -- `JournalingRepository`, the decorator the
  stage-0 `repository_factory` hook was left for. It puts a `rev` on every
  document it writes, bumped only when the document actually changed, and
  appends a per-document journal of what this device owes. **It is off by
  default and constructed only when sync is on**, so a signed-out device has no
  journal file, no `rev` and no cost -- checked first, because that promise is
  the one a later refactor breaks quietly. Adoption is automatic: a journal that
  has never met this library owes all of it, which is both "signing in does not
  migrate anything" (§9.2) and "losing `sync.db` is a re-push, not a data loss".
  The journal earns its place on deletes: `sweep()` reclaims a deleted score's
  row and `_drop_empty_pieces` removes a piece with no tombstone phase at all,
  and after either there is nothing left in the library that remembers. Proved
  by `engine/scripts/check_sync.py`.
- `VersionGraph.swift` -- rule 2 made real: forks found, `latest` resolved by
  timestamp with the tie broken by id so two devices rank a history the same
  way, siblings for the branch one tap away, and a child that arrived before its
  parent deliberately NOT announced as a fork. `VersionDoc` gained `parent`,
  which the manifest always carried and nothing decoded.
- `SyncMerge.swift` -- rules 3 and 4: the changed-field payload for an
  `updateData`, per-field merge in which a field this device still owes keeps
  its local value, and a tombstone that wins from either side and keeps nothing
  but the identity.
- `ArtifactHolding.swift` -- §5.1's holding policy, §5.2's three tiers behind
  one setting, and §5.4's eviction, including the check that section asks for by
  name: an artifact that has not been pushed is the only copy that exists and is
  never evicted, whatever the budget says.

Each of those was confirmed by reverting the fix and watching the test fail.
What is left in stage 1 is exactly the part that needs a Firebase project:
`SyncCoordinator` itself, Auth, App Check, the OMR server change, gzip on
upload, the two-libraries screen, and the `libraryId` that §9.2 wants written
into the database on first launch.

### Stage 2: a shared setlist you can read

Top-level shared setlists, invitations by named account, membership rules, the
`shared/` artifact prefix and its authorisation, the rights gate in full
(reference versus copy, the acknowledgement record, the book and source bans,
the cap of twelve), and roles with reader and owner only.

**What the user can do:** send a set list to their band, and everyone sees the
running order and can read every entry that shared as a copy.

**No annotation, no editing, no editor role.** This is on purpose: it exercises
membership, rules, cross-user artifact authorisation and the rights gate, which
are the parts most likely to be wrong, without any of the concurrency.

*Proves it:* rules tests for every role and every collection, including the
negative cases (a non-member can read neither the setlist document, nor its
entries, nor anything under its `shared/` Storage prefix); a test that a book
and a source have no share path at all; a test that a reference entry ships no
bytes.

### Stage 3: everyone marks up their own copy

Personal ink layers, per-member, synced. Layer visibility controls (mine,
everyone's, one person's). The repin flow from section 6.4.

**What the user can do:** the actual product ask, minus the shared layer. For a
band this is most of the value: everyone's cues, on the same running order, in
sync across their own devices.

*Proves it:* a rules test that a member can write only their own
`ink/{userId}` document and no other member's; a test that a member's ink
survives a repin and is still reachable; a measured check that a real dense page
of markup serialises well under Firestore's 1 MiB document limit, since that
number is currently an assumption rather than a measurement.

### Stage 4: the editor role and the band layer

Editors can reorder (fractional index), add, remove and repin. The band ink
layer as an append-only stroke set with compaction. The fork notice from
conflict rule 2.

**What the user can do:** the headline feature, complete.

*Proves it:* a convergence test that applies interleaved stroke additions and
erasures from three simulated members in randomised order and asserts every
ordering produces the same drawing; a reorder test where two editors move
different entries concurrently and both moves survive; a fork test where two
devices append offline to the same version and both children arrive.

### Deferred past stage 4

Presence, page-follow (one person turns the page and everyone follows, which
this data model makes nearly free and which should still wait until the band
layer is proven), public links (recommended never), a web client, and the
hosted agent loop from `ARCHITECTURE.md`, which is a separate project that
happens to need the same auth.

---

## 12. Risks and open questions

Each is a question for the owner, with a recommendation attached.

**12.1 Do version IDs become opaque now, or do we keep `vNNN` and renumber on
collision?**
*Recommendation: opaque now.* The refactor touches the CLI, the bridge, the app
and `CLAUDE.md`, and it is a week of unglamorous work with no user-visible
result. Deferring it means the fork rule in section 7 cannot be implemented
honestly, and the same refactor costs several times as much once two devices
hold divergent chains. This is the decision most likely to be regretted.

**12.2 Do shared-artifact reads pay a billed Firestore lookup each, or do we
mint custom auth claims?**
*Recommendation: pay the lookup.* The platform half of this is settled: Storage
rules can read Firestore, one document is well inside the two-document cap, and
section 4.3's layout is built around it. What is left is a cost preference. A
custom claim carrying the user's setlist IDs costs no billed
read but needs a Cloud Function on every membership change, a token refresh
before the client sees it, and it is capped at 1000 bytes, which is roughly
twenty setlists. Take the billed read; revisit only if it ever appears on a
bill.

**12.3 Does the owner's own fake book back up to his own bucket?**
*Recommendation: yes, opt-in per book, off by default.* It follows the posture
`ARCHITECTURE.md` already cites for Soundslice and Newzik, it makes the owner
choose rather than discover, and the default protects both the bill and the
risk. But this is a legal question with a business answer and it should have a
lawyer's view before anyone outside the household has an account.

**12.4 Anonymous auth for signed-out users, to get App Check on OMR?**
*Recommendation: no, not in stage 1.* Keeping the signed-out app free of any
Firebase contact is worth more than per-install OMR attribution while OMR is one
Cloud Run instance capped at one replica. Revisit if abuse appears, and if it
does, require sign-in for OMR rather than for launch.

**12.5 What is the monthly OMR page cap, and what happens at the cap?**
*Recommendation: 100 pages a month, matching the Soundslice model
`ARCHITECTURE.md` cites, with a hard stop and a clear message rather than
degraded service.* A cap that can be raised is a support ticket; an unexpected
Cloud Run bill is not recoverable. Needs a number from the owner.

**12.6 Does a shared setlist survive its owner deleting their account?**
*Recommendation: transfer, do not delete.* The band's running order and everyone
else's markup should not evaporate because one member left. On account deletion,
ownership passes to the longest-standing editor, and if there is none the
setlist becomes read-only and is deleted after a stated period. This needs to be
decided before stage 2, because it is a property of the data model, not a
feature that can be added later.

**12.7 Should sync push the whole version chain, or only from the point of
sign-in?**
*Recommendation: whole chain of documents, artifacts on the holding policy.* The
documents are kilobytes and the history is the product's distinguishing feature;
the bytes are what cost, and section 5.1 already withholds them. A partial
history would be the first thing a user noticed and the hardest thing to
backfill.

**12.8 Who is the first non-household user, and when?**
Not a technical question, and the one that decides how much of section 8 is
theory. Stage 1 is defensible with a household of one. Stage 2 is not shippable
to anyone until the ToS exists and the rights gate has been reviewed by someone
who is not an engineer.

**12.9 Under the flat permission model, may a member remove an entry someone
else added, and may a member remove another member?**
*Recommendation: yes to entries, no to members.* Principle 4 settles add,
reorder, invite and delete; it does not settle these two. A list anyone can add
to and nobody can prune fills with mistakes, so entry removal is a member act,
soft, attributed and restorable (§6.2). Removing a *person* is the mirror of
deleting the setlist -- it is the act that ends someone's access to their own
markup -- and it belongs with the owner. A member may always remove themselves.

**12.10 How is a member invited who signed in with Apple's Hide My Email?**
*Recommendation: an in-app invite code as the fallback, not a fix to the email
path.* Google SSO gives an address a bandmate already knows. Sign in with Apple
ships because guideline 4.8 obliges it (§0.4), and a private relay address is
unguessable by design, which is the point of it. A short-lived code the invitee
reads out or pastes covers the case without weakening the rule that a share adds
a named account. This needs designing before 0.7.3, not after.

**12.11 Does claiming an invitation go through a Cloud Function, or through
security rules on the verified email?**
*Recommendation: the Cloud Function.* §4.2. Membership is the one place §4.4
already names the server as authoritative, and a rule permitting a client to
write itself into a membership map is the highest-consequence rule in the system
to get subtly wrong. The cost is that it is the first deploy in the plan, which
makes it a question rather than a decision.

**12.12 Does the reference-versus-copy gate apply to an offline bundle?**
*Recommendation: no, and this is the one place section 13 is more permissive
than section 8.* A reference entry with no bytes, handed over AirDrop, is a file
containing a list of titles. The gate exists to stop *scaled, persistent* copies
accumulating on an operator's servers; a single chart passed to one person is
the act it was protecting against the multiplication of. The book and source
bans still hold absolutely. If the owner disagrees, the alternative is that
bundles carry only arrangements with the sharer's own work in them, which is
computable from the same version-`op` chain §8.1 already uses.

**12.13 Is the copy-versus-reference gate going to gut the feature for this
library?**
*No recommendation; this needs the owner's judgement and possibly a lawyer's.*
The gate is computable and principled: a chain of only `import`, `import-pdf`
and `book-extract` ops is material that arrived from outside, and it shares as a
reference with no bytes (§8.1). The problem is empirical. This library is
publisher PDFs, IMSLP scans and a commercial fake book, so **most entries in a
real setlist would share as references**, and a shared setlist in which most
entries show a title and a line saying "bring your own copy" is not obviously
the feature principle 2 asks for.

Three ways out, and they are genuinely different postures:

- **Keep the gate strict.** The feature is honest and, for this library, thin.
  The reference mechanism does have real value -- the band shares the *set*, each
  player brings their own copy -- and for a band who all own the same fake book
  it is arguably the correct model rather than a degraded one.
- **Copy with a recorded acknowledgement, per entry** (§8.2 guard rail 5, which
  already exists for exactly this). Friction where the risk is, a record naming
  who decided and who it reached, and the feature works. *This is the one I would
  build*, because the guard rail is already designed and the record is what makes
  a takedown answerable.
- **Exempt a private group below some size.** Attractive and I would not do it:
  it is a legal judgement dressed as a product setting, and the cap of twelve is
  already the structural limit doing that work.

This is the highest-consequence open question in the document and it decides how
0.7.3 feels, not just how it is governed.


---

## 13. Sharing without the cloud

New 2026-09-04, principle 6 (§0.7). Nothing in this section needs an account, a
network, a Firebase project or a bill, and it ships before any of them exist.

### 13.1 What a bundle is

**One file. An arrangement, or a whole setlist, with its artifacts and its
annotations, self-contained.** It goes out through the system share sheet --
AirDrop, Files, Mail, a USB stick, whatever the receiver can accept -- and the
receiving device opens it by tapping it.

```
Morrisons Jig.scorbundle          (a zip, with a declared UTI)
  bundle.json                     manifest: format version, kind, exported-at,
                                  exporting app version, the documents
  scores/<scoreUid>/<versionUid>.musicxml.gz
  scores/<scoreUid>/<versionUid>.pdf
  ink/<scoreUid>/<versionUid>/p<N>.pkdrawing
```

`bundle.json` carries the score, piece and setlist documents exactly as §4.2
shapes them, minus anything cloud-only (`rev`, `synced_rev`, storage paths).
That is the point of building this first: the payload a bundle carries and the
payload a shared setlist entry carries are the same payload, and writing it down
here forces it to be round-tripped through a test before it is also a Firestore
schema (§0.7).

A zip, not a directory and not a custom container. `.mxl` is already a zip, the
engine already has `zipfile`, and a single file is what AirDrop hands over
cleanly.

### 13.2 What goes in, and what does not

**The pinned version, not the whole chain, by default.** A bandmate needs the
chart, not the arranging history. Measured on `sous-le-ciel-de-paris` (§1.2),
that is about 23 KB gzipped against 605 KB for all 29 versions. "Include the
full history" is a switch on the export, off by default, for the case of handing
work to another arranger rather than a chart to a player.

**Annotations, yours only.** Exporting a setlist you are in exports your own ink,
not the whole band's. Principle 5 says what is shared includes annotations; it
does not say a bundle is a way to redistribute other people's markup, and the
person who drew it is not in the room to be asked. A future "include everyone's
marks (they will be told)" option is a decision, not a default.

**Never a book, and never a source.** §8.2's guard rails 3 and 4 apply
unchanged. `create_book` remains the only way a book enters a library and there
is no affordance anywhere to send one out.

**Never the whole library in one file**, even though it is technically a setlist
export over everything. A 43-piece library is hundreds of megabytes and it is
the shape that turns a convenience into redistribution. Export is per
arrangement or per setlist.

### 13.3 What import does

**An imported bundle becomes new local documents with new local identity.**

The bundle carries the original `uid`s, and the receiving device does not adopt
them. It mints fresh ones and records `originUid`, `originVersionUid` and
`importedFrom` as provenance. The reason is that a uid is a claim on a document
in a namespace, and two people who both hold `01J…7Q` for a score neither of
them can see is exactly the collision stage 0 exists to prevent. Provenance is
enough for the two things it needs to answer: whether this arrangement came from
outside, and whether a later bundle from the same source is an update of it.

**Duplicates are flagged, not merged.** Importing a bundle of something already
in the library -- same `originUid`, or just a matching title -- offers a choice:
add it as a separate arrangement, or open the one already there. It never merges,
and it never overwrites. Merging two divergent version chains is the fork
problem of §7 rule 2 and it is not worth solving for a file that arrived over
AirDrop.

**Ink re-attaches by uid, which is the piece stage 0 deferred.** The annotation
key is still `<slug>/<versionId>/p<N>` (§11 stage 0, "what was built
differently"), and a slug is local -- the receiving device's slug for the same
piece is whatever `slugify` makes of the title it already has. So the bundle
keys ink by `(scoreUid, versionUid)` and the store must too. That deferral was
correctly reasoned at the time, on the grounds that it bought nothing until sync
existed; it now has a consumer, and finishing it is part of 0.7.0 rather than of
a cloud stage. `DrawingStore.migrateVersionKeys` is the precedent for how.

**Import is offered, never automatic.** Tapping a `.scorbundle` opens a screen
saying what is in it -- titles, page counts, whose marks, how big -- and asks.
A file that lands in Files and imports itself is not something anyone asked for.

### 13.4 The engine does the work, so it can be tested

Export and import are engine ops, not Swift:

```
scor bundle-export <score|setlist> --out <path.scorbundle> [--full-history]
                   [--ink <dir>]
scor bundle-inspect <path.scorbundle>          # read-only: what is in it
scor bundle-import <path.scorbundle> [--into-piece NAME]
```

The app calls them through the same bridge every other op goes through, and the
share sheet is `SystemShareSheet` (`ios/Scoranger/Score/SystemShareSheet.swift`),
which already exists and is already the sanctioned exception to the no-modal
rule for exactly this purpose.

Putting it in the engine is what makes it provable in the style the repo uses.
`check_bundle.py`: build a library, export an arrangement and a setlist, import
both into a *fresh* workspace, and assert the artifacts are byte-identical, the
version chain is intact, the ink re-attaches to the right page of the right
version, a book has no export path, and importing twice produces two
arrangements rather than one corrupted one. None of that needs a device.

The iOS half is a UTI declaration (`CFBundleDocumentTypes` and an exported type
identifier in `ios/project.yml`), an `onOpenURL` handler, and the import screen.

### 13.5 The rights posture of a bundle

Handing one bandmate a chart over AirDrop is a materially different act from
putting a publisher's scan on a service operator's servers where it is stored,
indexed and backed up. Materially different is not "no question", and this
section does not claim the difference makes anything lawful.

What the design does about it:

- **The book ban and the source ban hold** (§8.2 guard rails 3 and 4). The
  highest-risk object in the library has no export path at all.
- **The copy-versus-reference distinction of §8.1 does not apply here, and that
  is a decision.** A bundle is always a copy: a reference entry with no bytes,
  handed over AirDrop, is a file containing a list of titles, which is not a
  thing anyone would send. Person-to-person transfer of a single chart is the
  case the reference mechanism was protecting against the *scaled* version of.
  §12.12 puts this to the owner, because it is the one place this section is
  more permissive than section 8.
- **No acknowledgement dialogue.** A per-export rights prompt on an act this
  small trains people to dismiss prompts, which is §7 rule 7's argument applied
  to a different surface. The gate that matters is the one on cloud sharing,
  where the copies persist and the operator is a party.
- **Nothing is recorded**, because there is no server to record it on. A bundle
  leaves no trail, which is a property of the mechanism and worth the owner
  knowing rather than discovering.

### 13.6 Joining a set list: URL, QR, and with no internet at all

Answer 3: *"share by URL or QR code"*, and *"sharing must ALSO work with NO
INTERNET -- offline via AirDrop/local transfer + QR handoff, per principle 6."*

Three transports, and the important thing is that they do not all deliver the
same thing. **Two of them share ACCESS and one shares CONTENT, and conflating
them would promise something the platform cannot do.**

#### The URL, which exists

`scoranger://invite?id=<inviteId>`, built and parsed by `SharedInviteLink`. The
link is not a permission: it names an invitation addressed to one verified email
address and `claimInvite` refuses it from anybody else (§8.2 guard rail 1). It
travels over whatever the inviter already uses. Built in 0.7.0.

#### The QR code, which is the same URL

A QR code is an encoding of that URL and nothing more, so it inherits every
property above and needs no new server work: render the invite URL as a QR on
the inviter's screen, point the other iPad's camera at it, and the second device
follows the same `onOpenURL` path a tapped link does. `CIQRCodeGenerator` and
`AVCaptureMetadataOutput`; no dependency.

**It is worth having precisely because of the offline case**, which is why the
owner names them together. Two iPads in a room with no network cannot exchange a
tapped link -- there is no messaging app to tap it in -- but a camera pointed at
a screen is a working data channel with no infrastructure whatever.

#### Offline: what it can and cannot mean

**It cannot grant cloud access.** Membership lives in a Firestore document that
only `claimInvite` may write, and no amount of local transfer can write it. A
design that pretended otherwise would either need the client to write membership
maps -- the one thing §4.4 refuses -- or hand out a bearer token that works
without the server, which is exactly the link-as-permission model §8.2 rules
out. So:

**Offline sharing hands over CONTENT, immediately and completely, and QUEUES the
membership.** The two halves are separate and both are honest:

1. **The content is a `.scorbundle`** over AirDrop -- the set list, its entries,
   and every participant's ink, per §13.1-13.4. The receiving device can open,
   read, play and annotate all of it, offline, forever, with no account. That is
   principle 1 and it is the half that matters at a rehearsal.
2. **The membership is a queued claim.** The bundle carries the `inviteId` (or
   the QR does), the receiving device stores it as a pending invite, and the
   claim runs the next time that device has both a network and an account. If it
   never does, nothing breaks: the recipient keeps a full working copy that
   simply is not live.

**What the reader is told, in these words rather than in a spinner:** *"You have
the whole set list and you can mark it up now. Once you're online and signed in,
your changes will start syncing with the others."* A queued claim that presented
itself as joined would show a running order that silently never updates, which
is worse than saying so.

**The bundle's copy and the shared entry are reconciled, not duplicated.** A
device that receives a bundle offline and later claims the invite must not end
up with the set list twice. The bundle records the `setlistId` and each entry's
id, so the claim adopts the local copies as those entries' cached content --
`SharedEntryCopies` already maps entry to local slug and this writes that map
ahead of time rather than after a download. The bytes are already on the device;
the claim only makes them live.

*Proves it:* a bundle imported with no network and no account yields a readable,
annotatable set list; the pending claim survives a relaunch; claiming it later
produces exactly one set list and re-downloads nothing; a bundle whose invite
was revoked in the meantime still leaves the content readable and says the
invitation is gone; and two devices that both received the same bundle offline
each claim their own invitation without colliding.

#### Which transport a person actually picks

They do not pick. The share sheet offers one action per situation and names the
consequence: **Invite somebody** (needs a network, they get access), **Show a QR
code** (needs a camera and a network on one of the two devices, same outcome),
and **Send a copy** (needs neither, they get the music now and access later).
Three buttons, three sentences, no mode.

---

# 6A. Sharing, reworked (2026-09-09)

Replaces the sharing UX in §6.2's presentation, §6.7's band, and the whole of
the "Shared with the band" surface. The data model in §6.1, §6.3, §6.4 and §6.5
is unchanged: pinned versions, per-member ink, fractional order.

## 6A.0 One thing needs Ali's sign-off first

**This direction requires amending guard rail 1 (§8.2), which currently reads:**

> *Sharing is to named people, never to a link. No "anyone with the link" mode,
> in v1 or later. A share is an invitation to an account. This removes the entire
> category of accidental public redistribution, which is the only category that
> turns into a takedown.*

A share button that opens the iOS share sheet cannot address a named account:
the owner never types an address, and whoever the message reaches can open the
link. `SetlistInvite` binds `emailLower` at construction and `claimInvite`
refuses any other account, so the current code implements guard rail 1 exactly
and cannot serve this flow.

Three ways to reconcile it, with a recommendation.

| Option | Owner's taps | Forward risk | Fits Ali's words |
|---|---|---|---|
| a. Keep email binding, share sheet sends a link the recipient can only claim from that address | share, then type the address | none | no, he asked for no address entry |
| b. **Slot-bounded expiring link** | share | bounded by cap and expiry, every claim recorded, revocable | yes |
| c. Single-use link, one per recipient | share once per person | lowest of the link options | yes for one person, breaks a band chat |

**Recommend (b).** §0.5 already conceded that with member invitation "the cap is
the only structural limit left between a band and a distribution list", so a
slot-bounded link changes the posture less than it looks. It gives the exact
flow asked for, keeps twelve as the enforced ceiling, keeps the record of who
joined, and adds revocation the email model never had.

Residual risk, stated so it is a decision: a link forwarded before the slots
run out admits whoever opens it. Mitigations are the cap, the 7-day expiry,
revoke, the visible member list, and owner-only removal. §8.3 already reserves
the rights question for a lawyer before anything ships outside the household;
this belongs in that review.

**CONFIRMED by Ali, 2026-09-09: option (b).** A slot-bounded expiring link --
cap 12, 7-day expiry, revocable. The client work is unblocked and everything
below is in force.

### 6A.0.1 Guard rail 1, as amended

§8.2 guard rail 1 previously read *"Sharing is to named people, never to a
link. No 'anyone with the link' mode, in v1 or later."* That sentence is
**superseded for set lists**, and this replaces it:

> Sharing a set list is by a link that admits WHOEVER OPENS IT, bounded four
> ways: at most 12 members including the owner, enforced transactionally in
> `claimInvite`; the link expires 7 days after minting; the owner may revoke it
> at any time; and every join is recorded with who and when, in a member list
> the owner can see and remove people from.
>
> What does NOT change, and this is the part of the old rule that survives
> intact: no public link, no link granting unbounded access, no link outliving
> its slots or its week, and no path by which a book or a source is shared at
> all -- guard rails 3 and 4 stand unamended.

**The residual risk, recorded as a decision and not an oversight:** a link
forwarded before the slots run out admits whoever opens it. The owner finds out
-- the member list shows every join -- and can remove them and revoke the link,
but the copy of the arrangement already downloaded is on their device. That is
the exposure accepted in exchange for one-tap sharing.

The mitigations are the cap, the expiry, revocation, the visible member list and
owner-only removal. §8.3 stands untouched: the rights question goes to a lawyer
before anything ships outside the household, and this amendment belongs in that
review rather than instead of it.

## 6A.1 One kind of set list

There is one set list object. Sharing is a **field on it**, not a second kind.

Engine, `workspace.create_setlist` document gains two nullable fields:

```
shareId:  str | None    the Firestore setlists/{id} this row is bound to
ownerUid: str | None    who owns it there; None means this device owns it
```

Nullable and defaulted, so every existing document decodes unchanged.

`SetlistDoc` in `Models.swift` gains `var shareId: String?` and
`var ownerUid: String?`, both optional, same reason.

**Promotion is in place.** On the first share of a local set list:

1. Create `setlists/{id}` in Firestore with `ownerId` = this account.
2. For each slug in the local `scores[]`, pin its **current latest version** and
   write an entry `(scoreUid, versionUid)` with a fractional index preserving
   the local order (§6.5).
3. Upload the artifacts those entries name (§4.3).
4. Write `shareId` back to the local document.

The row does not move, does not change identity, and keeps its slug and uid. The
owner gains no new object, which is item 3 of the direction.

**After promotion the shared entries are authoritative for order and
membership of the list**, and the local `scores[]` is a projection of them. One
list, one truth. A set list with `shareId == nil` behaves exactly as today with
no Firestore involvement at all.

## 6A.2 The share control

On the row, immediately leading of the `☰`. Not in the `☰` screen: a control in
two places is what `optionsCarriesTransportToggle` exists to prevent.

```
│ Tuesday at the Ship                          ⇪   ☰ │
│ 6 arrangements · 4 people                          │
```

- `square.and.arrow.up`, a 34pt bordered square in a 44pt hit target, identical
  to `RowMenuButton` in every respect but its glyph. Identifier
  `row-share-<id>`, label `Share <name>`.
- `Theme.Metric.rowMenuInset` gains a two-control value: `8 + 44 + 44 + 8 = 104`
  against the current 60. Measured against the row's text:

| | Row | Text | Characters at 13.5pt |
|---|---|---|---|
| iPhone portrait, A–Z rail | 377 | 253pt | ~33 |
| iPhone landscape, capped at 560 | 544 | 420pt | ~56 |
| iPad 13", reading column | 704 | 580pt | ~77 |

  Fits at every width. Per §6.3 rule 1 of `IPHONE_0.6.14.md` the inset is
  derived from `hitTarget`, never a literal 104.

- **Set lists only.** No share control on a piece, a book or a source: guard
  rails 3 and 4 are unchanged and are not a UI decision.
- **Signed out it is still there**, and tapping it pushes sign-in with one line
  saying why, then continues to the share sheet on success. Principle 1 gates
  the *act*, never the app, and a control that materialises after sign-in is
  worse than one that explains itself.
- The row's meta line gains `· N people` only when `shareId != nil`. That is the
  only visible difference between a shared and an unshared set list, and it is a
  fact about the list rather than a category.

## 6A.3 The link

**A universal link, not the custom scheme.** `scoranger://invite?id=…` does not
render as a tappable link in Messages or Mail for anyone without the app
installed, which is most first-time recipients. Use
`https://<domain>/i/<inviteId>` with an `apple-app-site-association` file and a
web fallback page that offers the App Store.

`SharedInviteLink` keeps the custom scheme as the **paste** fallback it already
implements, and gains the https form. Infra dependency: the domain and the AASA
file have to exist before this ships. Flagged as the one item here that is not
client work.

The invite document changes shape:

```
slots:     Int      remaining claims, minted as (12 − current members)
expiresAt: String   7 days from minting
createdBy: String   unchanged
emailLower           REMOVED
claims:    [{ uid, at }]   appended per claim, for the record §0.5 requires
```

Rules enforce: `slots > 0`, `now < expiresAt`, member count `< 12`. A claim
decrements `slots` in the same transaction that writes membership.

Share text, subject and body:

```
Subject:  Tuesday at the Ship
Body:     Tuesday at the Ship, a set list in Scoranger.
          https://<domain>/i/7f3a…
```

Nothing about the music, no piece titles. The invite carries the set list's name
and nothing else, which §4.2 already requires.

## 6A.4 The owner's flow, including the failure

Tap `⇪`:

1. Signed out: push sign-in, then continue.
2. `shareId == nil`: promote (§6A.1). This is network work and it can fail.
   While it runs the row's meta line reads `Preparing to share…`; the row stays
   tappable and nothing is modal.
3. Mint an invite with `slots = 12 − members`.
4. Present `UIActivityViewController` with the URL and subject.

Failure, offline or rules-rejected: an inline notice bar in the library,
`Couldn't make a link. Try again when you're online.` The set list is unchanged
and unpromoted; there is no half-shared state, because step 4 is reached only
after 1 through 3 commit.

Already shared: skip step 2, mint a fresh link, share it. Sharing twice is two
links, both valid until they expire or the slots run out.

## 6A.5 The recipient

Opening the link, signed in, pushes one screen:

```
  Tuesday at the Ship
  Shared by Ali Momeni
  6 arrangements

  [ Add to my set lists ]
```

Confirm, and the set list appears in Setlists as a normal row. The screen pops
to it.

**One confirmation, no holding area.** Ali asked for no "you've been invited"
area and this is not one: the persistent library band goes, and what remains is
a single step at the moment of opening. It stays because joining downloads
another person's copies of another person's music onto this device, which is the
reason `SharedSetlistsBand` gave for not claiming silently and it is still the
right reason. If Ali wants it gone too, say so and it becomes a one-line change,
but I would not remove it unasked.

Signed out: the same screen, with sign-in first. The invite is held in memory
until sign-in completes, and **not** surfaced in the library.

Joining writes a **local set list document** with `shareId` set and `ownerUid`
the owner's, then imports the entries' artifacts through the existing
`SharedEntryCopies` path. That local write is what makes item 5 work: the
recipient's Setlists list gains an ordinary row, with no special case anywhere in
`LibraryView`.

Refusals, each with its own line on that screen: expired, no slots left, set
list full, already a member (which opens it instead).

## 6A.6 Permissions, without a band

§6.2's table is unchanged. Its presentation moves to the set list's own `☰`
screen, as one row:

```
People                                    4
```

Pushing it lists the members, the owner marked, with:

- Owner: `Remove` on each other member, and `Delete this set list`.
- Member: `Leave this set list` on themselves only.
- Anyone: add, reorder, remove and repin entries, as §6.2 says.

The word band does not appear. Neither does shared. A member list is a fact
about this set list, reached from the set list, and every string is about people
rather than about a category of object.

The cap surfaces in one place: when `members == 12` the share control is
disabled with the accessibility hint `This set list is full`.

## 6A.7 What is deleted

- `Account/SharedSetlistsBand.swift` entirely: the band header, the
  `shared-none` note, the `shared-row-*` rows, `shared-new`, and the
  `pendingInvite` invitation panel.
- `AppState.pendingInvite` as a *published library surface*. The value stays as
  transient state for §6A.5's screen.
- `SetlistInvite.emailLower` and its normalisation, with `claimInvite`'s
  address check.
- Any string containing "shared set list", "Shared with you", "You made this",
  or "band" in the library.

`SharedSetlists`, `SharedSetlistScreen`, `SharedInk`, `SharedOrder`,
`SetlistPermission`, `SharedEntryCopies` and `InviteQRCode` all survive.
`SharedSetlistScreen` stops being a separate destination and becomes what the
one set list screen shows when `shareId != nil`.

## 6A.8 For the engineer

The "promotion is not supported" answer was right about the code and it is a
smaller change than it sounds, because nothing about §6.1's entry model moves.
What is actually new:

1. Two nullable fields on the setlist document, engine and Swift.
2. A `promote(slug:)` path: create, pin, upload, write back `shareId`. Steps
   already exist separately for the create-shared-fresh flow; this composes them
   over an existing local list.
3. Reading order from shared entries when `shareId != nil`, and from local
   `scores[]` otherwise. One branch, in the model layer, not in the views.
4. The invite shape change in §6A.3 plus the matching rules.
5. Join writes a local setlist row rather than only a membership.

The one item outside the app: the domain and `apple-app-site-association` for
§6A.3.

Open question for you, not for Ali: on promotion, do we pin the latest version
of each arrangement *at that moment* (my assumption, and what §6.1 implies), or
the version the owner last had open? I assumed latest. Say if that is wrong.

## 6A.9 Acceptance

1. `oneKindOfSetlist`: no view reads a "shared" collection to build the Setlists
   list; a grep for `SharedSetlistsBand` finds nothing.
2. `shareIsOnTheRow`: `row-share-<id>` and `row-menu-<id>` both have frames
   inside the row at 393pt, and the row's title is not truncated for a 30-character
   name.
3. `promotionKeepsIdentity`: after promoting, the set list's slug, uid and
   position in the list are unchanged, and its entry order matches the local
   order it had.
4. `promotionIsAtomic`: with the network refused, the set list is left with
   `shareId == nil` and no partial Firestore document.
5. `joinAddsANormalRow`: claiming an invite writes a local setlist document, and
   the resulting row renders through the same `LibraryRow` path as any other.
6. `capHolds`: a thirteenth claim is refused by the rules, and the share control
   is disabled at twelve.
7. `noAddressBinding`: `SetlistInvite` carries no email field, and a claim from
   any signed-in account with slots remaining succeeds.
8. `signedOutCostsNothing`: `check_signed_out.py` still passes. The two new
   fields are nullable and a signed-out device journals nothing.
