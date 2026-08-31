# Firebase integration: sync, sharing and the rights gate

Design document, 2026-08-30. Written against `dev` at 42b6fa3. No app code has
been changed. Target: the minor version after playback.

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
    name, ownerId, createdAt, members: { userId: "owner"|"editor"|"reader" },
    memberIds: [userId], rightsAcknowledged: [...]
    entries/{entryId}       order (fractional index), title, composer,
                            scoreUid, versionUid, mode: "copy"|"reference",
                            storagePath, pages, addedBy, addedAt
        ink/{userId}            layer: "personal"|"band", updatedAt, compactedRev,
                                pages: { "3": <PKDrawing bytes>, ... }
            strokes/{strokeId}  page, data (one-stroke PKDrawing), createdAt,
                                deletedAt        (band layer only)

memberships/{userId}_{sharedSetlistId}
    setlistId, userId, role, setlistName, joinedAt
```

Three shapes in there are decisions rather than transcription.

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

Three, deliberately few:

| Role | Read | Personal ink | Band ink | Reorder, add, remove, repin | Invite |
|---|---|---|---|---|---|
| Reader | yes | yes | no | no | no |
| Editor | yes | yes | yes | yes | no |
| Owner | yes | yes | yes | yes | yes |

A reader who can annotate is the common case and the important one: hand a
setlist to a dep player and they mark their own part without any risk to
anyone's running order. Inviting stays with the owner in v1 because invitation
is the act with rights consequences (section 8) and it should have one
accountable person.

### 6.3 Annotation by several people, concretely

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

Sign-in method in stage 1 is **Sign in with Apple, and only that.** It needs no
password handling, Hide My Email means the app never holds a real address, and
shipping it alone keeps the app outside App Store guideline 4.8 entirely: that
guideline obliges an equivalent private option only when a third-party or social
login is offered, so adding Google Sign-In later is what would create the
obligation. Add others when there is a reason to.

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

Five stages. Each is independently shippable, each leaves the app in a state
worth having, and each has something that proves it in the style the repo
already uses: a `check_*` script that fails without the fix.

### Stage 0: stable identity

**Nothing user-visible ships.** Every document gets a ULID `uid`; version IDs
become opaque with `vNNN` as a derived label; the annotation key moves to
`(scoreUid, versionUid, page)`; `db.py` gains a `Repository` protocol and
`workspace._repo()` gains a factory; a `changes` journal table and `rev` /
`synced_rev` fields land unused. The `FirestoreRepository` promise in `db.py`'s
module docstring and in `CLAUDE.md` is replaced with a pointer to this document,
because a stale plan in the file every contributor reads first is worse than no
plan (section 1.1).

*Proves it:* `check_identity.py` (a rename does not change any `uid`; two
versions created from the same parent get distinct IDs; every existing workspace
migrates with no loss), plus the existing suite green, especially
`check_workflows.py`, `check_undo.py` and `check_bridge_ops.py`.

*Deliberately not in this stage:* any network code, any Firebase dependency in
the Xcode project.

Do this one first even if the rest slips. It is a strict improvement on its own
(it deletes `DrawingStore.rename` and its orphaning bug), and every later stage
is unbuildable without it.

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
