# Gate duration: where the time goes and what to do about it

Analysis only. Nothing in the test suite has been changed.

**Bottom line.** 43.6 of the gate's 76 test-minutes are spent in three classes
that contain **zero assertions** and therefore cannot fail a gate. A further
15.0 of those minutes are a verbatim duplicate class. A further 6.1 minutes are
hard-coded `sleep()`. Removing the assertion-free harnesses from the gate and
replacing the engrave sleeps with a condition wait takes the test phase from
~76 min to ~29 min with **no assertion removed and no test deleted** — the
harnesses stay in the repo and stay runnable on demand. Parallelisation is a
second, riskier factor of two on top; the per-test seeding cost that looked like
the obvious culprit is measured at 1.05 s and is not worth attacking.

## Method

Parsed 32 `gate*.log` files (2026-08-26 → 2026-08-30) from the scratchpad.
Per test: `Test Case '-[Class name]' passed (N seconds)`. Per test: the XCTest
activity stream (`t = N.NNs …`), which gives launch boundaries, setUp/body
split, screenshot cost, and silent gaps. Where a test appears in several runs I
use the **median**. Inventory of what exists *now* is read from `dev` @
`452eb9c`; a test present in the logs but gone from the source is excluded.

Build time is not in the logs and is not measured here.

## 1. Where the time goes

### The one complete run in the corpus

`gate3.log`, 2026-08-29 21:01:50 → 22:06:48, one simulator, `xcodebuild test
-scheme Scoranger`, no test plan, no parallelism.

| Phase | Tests | Wall |
|---|---:|---:|
| `ScorangerTests.xctest` (pure logic) | 470 | **1.43 s** |
| target teardown / UI runner install | — | 6.0 s |
| `ScorangerUITests.xctest` | 105 | **3890.9 s** |
| **Total test phase** | **575** | **64.97 min** |

Inside the UI target:

| Class | Tests | Time | Assertions in the file |
|---|---:|---:|---:|
| `ScorangerUITests` | 73 | 31.59 min | 387 |
| `DesignerSweep` | 11 | 15.04 min | **0** |
| `VisualSweep` | 11 | 14.97 min | **0** |
| `RowShot` | 9 | 2.57 min | **0** |
| `InkShot` | 1 | 0.69 min | 3 |

### Projected cost of the current test set

`DesignerSweep` has grown from 11 tests to 16 since that run. Applying medians
to today's inventory:

| Class | Tests | Projected |
|---|---:|---:|
| `ScorangerUITests` | 75 | 32.13 min |
| `DesignerSweep` | 16 | 25.97 min |
| `VisualSweep` | 11 | 14.99 min |
| `RowShot` | 9 | 2.58 min |
| `InkShot` | 1 | 0.70 min |
| **UI total** | **112** | **76.36 min** |
| `ScorangerTests` | ~490 | 1.4 s |

**The top ten tests are 29.4 min — 38% of the whole UI cost. Nine of the ten are
assertion-free screenshot sweeps.**

| Median | Test |
|---:|---|
| 239.4 s | `DesignerSweep.testCharacteriseContinuous` |
| 187.9 s | `VisualSweep.testSweepWhistlePortrait` |
| 187.8 s | `VisualSweep.testSweepWhistle` |
| 187.6 s | `DesignerSweep.testSweepWhistle` |
| 187.6 s | `DesignerSweep.testSweepWhistlePortrait` |
| 187.5 s | `DesignerSweep.testSweepMarksAndAccidentals` |
| 176.1 s | `VisualSweep.testSweepLibraryPortrait` |
| 175.3 s | `DesignerSweep.testSweepLibraryPortrait` |
| 135.9 s | `DesignerSweep.testSweepLibrary` |
| 98.0 s | `VisualSweep.testSweepLibrary` |

The first test with an assertion in it is 11th:
`testTheZoomedPageUsesTheWholeCanvas`, 95.0 s. Top 20 = 42.6 min = 56%.

### The unit cost of everything

Activities per second, per class, in `gate3`:

| Class | Activities | Seconds | s/activity |
|---|---:|---:|---:|
| `ScorangerUITests` | 7637 | 1895 | 0.248 |
| `DesignerSweep` | 3417 | 902 | 0.264 |
| `VisualSweep` | 3418 | 898 | 0.263 |
| `RowShot` | 475 | 154 | 0.324 |
| `InkShot` | 174 | 41 | 0.238 |

**One XCUI accessibility query costs ~0.25 s on this app.** The gate's duration
is very nearly `0.25 × (queries) + 5.3 × (tests) + (sleeps)`. Nothing else
matters. This is the single most useful number in the document: it tells you
that a control lookup is worth a quarter of a second, and the sweeps do 3400 of
them.

## 2. Fixed per-test overhead — and why re-seeding is *not* the problem

Every `ScorangerUITests` test launches with `-resetLibrary -seedTestLibrary`,
which deletes the on-device workspace (`PythonEngine.start`,
`ios/Scoranger/PythonEngine.swift:35`) and re-imports the sample `.mxl` files
through embedded CPython (`AppState.seedLibraryIfEmpty`,
`ios/Scoranger/AppState.swift:871`).

Measured `setUp`: **median 5.3 s, min 5.2, max 5.9, across 24 runs.** Rock
steady. Broken down from the activity stream of `testTheFABIsGone` (total 5.58 s,
body 0.26 s):

| Step | Cost |
|---|---:|
| terminate + relaunch + automation session | 1.8 s |
| `ActivityListView` probe (stale system sheet guard) | 1.2 s |
| wait for `library-search` | 1.1 s |
| **wait for the seeded row — i.e. the re-import** | **1.05 s** |

75 tests × 5.3 s = **6.6 min, 21% of the assertion suite.**

**Recommendation: do not pre-seed a shared workspace.** The re-import is 1.05 s
of the 5.3 s. A shared prepared workspace would save at most 1.3 min across the
gate and would cost the isolation that `-resetLibrary` buys — and these tests
rename, delete and reorder things. The suite's own comment says why the flag is
there. This was the leading hypothesis going in; the data does not support it.

What *is* available in setUp, cheaply: it uses
`app.descendants(matching: .any)["library-search"]`, an any-type walk of the
whole SwiftUI tree. The sweeps use the typed `app.textFields["library-search"]`,
and `VisualSweep.swift:56` records why: an `.any` descendant walk once grew the
runner until the system killed it. There are 33 `.any` descendant queries in
`ScorangerUITests.swift`, one of them on the setUp path of all 75 tests.
Switching those to typed queries is mechanical. Estimated saving 0.5–1 min;
the real reason to do it is the crash the comment describes.

## 3. Nineteen per cent of the assertion suite is literally asleep

Silent gaps of ≥3.5 s with no activity between them — that is a `sleep()`:

| Run | Class | Total | Idle | % |
|---|---|---:|---:|---:|
| gate3 | `ScorangerUITests` | 31.59 m | **6.12 m** | 19% |
| gate12 | `ScorangerUITests` | 28.30 m | **5.13 m** | 18% |
| gate3 | `RowShot` | 2.57 m | 0.44 m | 17% |
| gate3 | sweeps | 30.0 m | 0.10 m | 0% |

`ScorangerUITests.swift` contains 49 unconditional `sleep(N)` calls totalling
241 s of source. **177 s of that sits immediately after the line
`XCTAssertTrue(canvas.waitForExistence(timeout: 180), "the score never
engraved")`** — sixteen sites, `sleep(6)` to `sleep(25)`, all waiting for the
engrave that the canvas's existence does not prove.

The condition is already observable. The app publishes a per-page identifier —
`canvas-sous-le-ciel-quartet/v003/p0` appears throughout the activity stream —
and `testTheZoomedPageUsesTheWholeCanvas` already waits on an
`identifier ENDSWITH "/p0"` predicate instead of sleeping. The other sixteen
sites can use the same wait. **The assertions do not change at all.**

## 4. Parallelisation

Host: `Mac17,7`, 18 cores (6 P + 12 E), 128 GB, Xcode 26.6. The scheme
(`ios/project.yml:258`) lists both targets, has no test plan, and the gate does
not pass `-parallel-testing-enabled`.

`xcodebuild` distributes **test classes** across simulator clones. With today's
five UI classes the critical path is `ScorangerUITests` at 32.1 min — so
parallelism alone takes 76 → ~32 min, and combines badly with §5 (once the
sweeps are off the gate, only one big class is left and parallelism buys
nothing). **To keep helping, `ScorangerUITests` must be split into sub-classes.**

Specifically what would break under a split, not "it might":

1. **`@AppStorage` keys that `resetViewPreferencesForTesting` does not clear.**
   It resets `scoreLayout` and `DrawingStore` only (`AppState.swift:779`). Not
   cleared: `chatInputLines2` (written by `testTheChatBoxKeepsItsResizeGrip`),
   `showTransport`, `touchDiagnostics`. Readers of the first:
   `testCanvasFillsTheGapBesideTheChatPanel`, which asserts the chat panel is
   exactly 380 pt wide; `testChatOverlayOpensFromAsk`; `RowShot.testChatPanel`.
   Today alphabetical order happens to run `testTheChatBox…` (T) after
   `testCanvasFills…` and `testChatOverlay…` (C), so the leak is masked by
   naming. Split them across classes and the ordering guarantee is gone.
   **Fix before splitting: extend `resetViewPreferencesForTesting` to clear all
   three keys.** One line, and it removes a latent order dependency that is
   already fragile.
2. **`DesignerSweep`'s whistle fixture is placed by hand on one simulator.**
   `testSweepWhistle`, `testSweepWhistlePortrait` and
   `testSweepMarksAndAccidentals` (187 s each) read a file dropped into that
   device's `Documents/inbox` out of band (`DesignerSweep.swift:414, 525`).
   Cloned simulators do not have it. Because the class has no assertions they
   would not fail — they would silently screenshot an empty library for 9.4 min.
   See §6: they already do this.
3. **Not a problem:** the stale-system-sheet guard in setUp handles the sheet
   `testExportingMusicXMLRaisesTheSystemShareSheet` leaves standing, defensively,
   on every test. `testAnEmptyLibraryIsAStateWithSomethingToDo` relaunches
   without the seed, but the next test's own setUp re-seeds. Both survive a split.
4. **Contention.** Four clones each running embedded CPython plus Verovio on 18
   cores. The `waitForExistence` timeouts (90/180/240 s) have ample headroom, but
   the 49 fixed `sleep()` calls do not adapt — a slower machine makes them *less*
   safe, not more. Doing §3 first is a precondition, not an optimisation.

## 5. Genuine redundancy: less than you would hope, and one enormous exception

I looked for UI tests asserting a property a pure test already proves. **With
one exception, they are not redundant, and I recommend keeping them.** The
pattern is consistent: the pure test proves the *rule*, the UI test proves the
rule is *wired to a control and reaches the screen*.

`ScoreLayoutTests.testContinuousHasNoPageCounter` (3 ms) proves the rule.
`testContinuousLayoutShowsOneStripAndNoPageCounter` (26.6 s) proves the layout
button reaches it, and also asserts
`app.buttons.matching(identifier: "score-title").count == 1` — that the score
screen is not drawn twice. No logic test can catch that, and it is exactly the
class of bug this codebase has shipped. Same verdict for
`testCanvasFillsTheGapBesideTheChatPanel` against `PagedCanvasTests`: the UI
test guards the live frame *after a panel opens*, which is the build-120 defect
its own comment names.

**Merging cheap tests is not worth it.** Thirteen tests have a body under 5 s
and cost 96.7 s in total, of which 68.9 s is setUp. Merged into three tests
(library chrome / Settings / zoom) they would cost ~40 s — a saving of **57 s**,
about 1.2% of the gate, in exchange for losing per-property failure isolation
(`continueAfterFailure = false`, so the first failure hides the rest of the
merged test). Bad trade at this scale. Named here so it is a decision rather
than an oversight.

**The exception is `VisualSweep`.** `DesignerSweep.swift` is a verbatim fork of
`VisualSweep.swift` made on 2026-08-29 — its own header says so — with five
tests added. Its 11 original tests have identical names and identical bodies. In
`gate3` the two classes ran **3417 vs 3418 activities, 59 vs 59 screenshots,
902.3 s vs 898.0 s**. That is 15.0 min of byte-identical duplicate work on every
gate. `DesignerSweep`'s 16 tests are a strict superset.

## 6. The screenshot harnesses

`DesignerSweep`, `VisualSweep` and `RowShot` contain **no `XCTAssert` of any
kind**. Both sweep files describe themselves as "a screenshot sweep, not an
assertion suite … not part of the shipped test suite's contract." They cost
**43.6 min per gate** and cannot fail one.

They are also drifting, invisibly. `gate3` printed **88 `SWEEP:` miss
diagnostics**, including:

```
4 × SWEEP: the whistle fixture never imported
8 × SWEEP: no element library-edit
8 × SWEEP: no element library-add
8 × SWEEP: no element score-spread
4 × SWEEP: no element library-settings
```

`score-spread` was deliberately replaced by the three-way layout control;
`library-add` was deliberately removed with the FAB. The sweeps are still
hunting for them. Each miss runs `candidates(id)` — six typed queries, each
probed for `.exists` and `.isHittable` — then a 4 s `waitForExistence`, then the
six again: **~12 queries at 0.25 s plus a 4 s timeout ≈ 7 s per missed control**
(estimate, from the measured per-query cost; the miss itself is not timestamped).
88 misses ≈ **10 min of gate3's 30 sweep-minutes spent timing out on controls
that no longer exist.** And the three whistle tests — 9.4 min — screenshotted an
absent score.

Screenshots themselves are not the problem: 1.07 s each in the sweeps
(`XCUIScreen.main.screenshot()` plus a `settle`) versus 0.12 s in the assertion
suite (`app.screenshot()`), 65 s per sweep class per run. The cost is the 3400
accessibility queries.

**`DesignerSweep` belongs to the designer and I am not proposing to touch it.**
The proposal is only that it stops running on the engineer's gate.

## 7. Recommendations

Ordered as asked: make the same tests faster, then run fewer things per gate,
then trade assurance. Savings are against the 76.4 min projected test phase.

### Safe and mechanical — no assertion changes, nothing deleted

| # | Change | Saving | Risk |
|---|---|---:|---|
| R1 | Add an `.xctestplan` (or a second XcodeGen scheme) `Scoranger-Gate` that runs `ScorangerTests`, `ScorangerUITests` and `InkShot` only. The sweeps keep their current scheme and their `-only-testing:` runbook — nothing is removed, only the default changes. | **43.6 min** | Loses a weak crash canary: a sweep walking 300 controls would notice a hang the assertion suite might not. Mitigate by keeping `DesignerSweep/testSweepEdgeStates` (23.6 s) on the gate. |
| R2 | Retire `VisualSweep` as a duplicate of `DesignerSweep`. Independent of R1; worth doing even if the sweeps stay. | **15.0 min** (subsumed by R1) | None to coverage. The fork exists so two people stop editing one file — settle that first, then delete the loser. |
| R3 | Replace the 16 `sleep(6…25)` calls that follow "the score never engraved" with a wait on `canvas-<slug>/<version>/p0`, the pattern `testTheZoomedPageUsesTheWholeCanvas` already uses. | **~3–4 min** | Low. A wait is strictly more correct than a sleep. Verify each rewritten test still fails against a build that does not re-engrave. |
| R4 | Bound the pinch loops in `testTheZoomedPageUsesTheWholeCanvas`: `for _ in 0..<24 where scale() < target` evaluates `scale()` — an accessibility read — all 24 times even after the target is reached. `while` with a break. | **~1.3 min** | None. |
| R5 | Replace the 33 `descendants(matching: .any)` queries with typed queries, starting with the one on every test's setUp path. | **~0.5–1 min** | None, and it removes the runner-kill the sweep header documents. |
| R6 | Run the 22 `engine/scripts/check_*.py` under `xargs -P 8`. All but one use temp workspaces; the exception (`check_structure.py`) uses `NamedTemporaryFile`. | **~1.5 min** | Low. Confirm no two checks race on `workspace/`. |
| | **Total, safe** | **~50 min → gate ≈ 26 min** | |

### Trades a little assurance for time — say so out loud

| # | Change | Saving | What is actually lost |
|---|---|---:|---|
| R7 | Split `ScorangerUITests` into 4 classes and run `-parallel-testing-enabled YES -maximum-parallel-testing-workers 4`. **Precondition:** clear `chatInputLines2`, `showTransport` and `touchDiagnostics` in `resetViewPreferencesForTesting` first, and do R3 first. | 26 → **~10–12 min** (assuming ≤1.3× contention; unverified) | Reproducibility. A failure on a loaded clone is harder to reproduce, and the fixed gesture timings are the part most likely to go flaky. Prove it with 3 consecutive green parallel runs before trusting it. |
| R8 | Merge the 13 sub-5-second tests into 3. | 57 s | Per-property failure isolation. **Not recommended** — 1.2% of the gate for a real loss. |

### Fix regardless of speed

- `testSweepWhistle`, `testSweepWhistlePortrait`, `testSweepMarksAndAccidentals`
  depend on a fixture placed by hand in one simulator's `Documents/inbox`. It
  was absent in `gate3` and the tests reported success. Either bundle the
  fixture in `samples-seed` behind a launch argument, as the other seeds are, or
  make the sweep `XCTFail` when its fixture is missing.
- The 88 `SWEEP:` misses are the sweeps asking for controls the app removed on
  purpose. They are burning ~10 min a run and telling nobody.

## 8. Recommended target

**A gate of ~26 minutes of test time, from ~76, with every assertion intact and
every file still in the repo.** That is R1–R6: stop running three assertion-free
harnesses by default, delete one duplicate class, and replace hard-coded sleeps
with the condition they were approximating.

What that costs:

- The screenshots stop being produced on every gate. They become a command the
  designer and the engineer run when they want them — which, given the sweeps
  are exported by hand with `xcresulttool` anyway, is how they are already used.
- The weak crash-canary property of walking 300 controls. Recovered for 24 s by
  keeping `testSweepEdgeStates` on the gate.
- Nothing else. No assertion is weakened, no property loses its only protector,
  and nothing is deleted that cannot still be run with `-only-testing:`.

R7 takes it to ~10–12 min but should be treated as a separate project with its
own proof: the `@AppStorage` leak fixed, R3 landed, and three consecutive green
parallel runs before it becomes the default.

For each of R3, R4 and R5 the project's own discipline applies — revert the fix
and confirm the test still fails — since all three touch how a test waits, and a
wait that no longer waits is exactly the no-op this project has caught before.
