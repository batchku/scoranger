# 0.4.1 revision — no context menus, paged canvas

Focused addendum to `NAVIGATION_SYSTEM.md`. Design only; no app code changed.
Mockups: `scoranger-nav-revision.html`, `png/rev-*.png`. Line references are
against the 0.4.0 tree (`e9d9957`).

**The rule this revision adds:** *a long press is never how you reach a feature.*
Every management action has a labelled, visible control.

> **Superseded by 0.4.2 (NAV_MODAL_FREE_0.4.2 §9).** This document said "drag
> stays as a fast path". It does not: dragging was removed from the app
> entirely. Wherever a table below offers drag as the quick way, the labelled
> control is now the only way. Page turns keep the §6.6 rule — a gesture may be
> the quick way, never the only way — because tap zones, the strip and the
> transport all still turn.

---

## 1. Every context menu, and where its contents go

Six sites carry a `contextMenu` today. All six are removed.

| # | Site | Carries | Replacement |
|---|---|---|---|
| 1 | `Navigation/LibraryManagement.swift:16` `RowContextMenu` | Open, Versions…, Details, Add to set list…, New arrangement, Rename…, Delete | Deleted as a type. Contents split between Edit mode (§2), the arrangement sheet (§3), and the row's own trailing controls |
| 2 | `Navigation/TabBar.swift:148` `LRow.contextMenu { menu() }` | the menu above, on every library and Home row | The `menu` generic parameter and the `LRow where Menu == EmptyView` overload both go; `LRow` keeps `action` only |
| 3 | `Navigation/LibraryManagement.swift:179` arrangement row inside `ArrangementSheet` | per-arrangement actions | Labelled buttons on the row (§3) |
| 4 | `ContentView.swift:796` legacy setlist row | Rename setlist, Delete setlist | Setlists segment Edit mode (§2.4) |
| 5 | `ContentView.swift:858` legacy setlist member row | Remove from set list | A visible `−` on the member row inside the setlist (§2.4) |
| 6 | `ContentView.swift:1002` legacy arrangement row → `arrangementMenu` | Move up/down, Duplicate, Move to piece, New piece…, Remove from piece, Delete | Edit-mode action bar and the Move-to-piece sheet (§2.2, §2.3) |

Sites 4–6 belong to the **legacy library overlay still living inside the score
screen** (`ContentView.libraryPanel:577`, opened at `:483` and bound into the
pill at `:1204`). Once §2 exists there is nothing left that only the overlay can
do, so this revision **deletes the legacy overlay, the pill's library button and
the dead `classicManager` state** (`RootView.swift:37`). After it, the score
screen has exactly one chrome: top bar, thumbnail strip, transport.

### Action inventory — every action's visible home afterwards

| Action | Home | Affordance | Suggested id |
|---|---|---|---|
| Open | row tap | whole row, chevron | `row-<id>` |
| Browse versions | ① score title dropdown ② arrangement sheet row ③ Edit-mode row button | `Versions` button | `edit-versions-<id>` (exists) |
| Arrangement details | arrangement sheet row; browse row trailing `ⓘ` | `Details` button / `ⓘ` | `row-details-<id>` |
| Rename | Edit-mode row button + action bar (1 selected) | `Rename` | `edit-rename-<id>` (exists) |
| Delete | Edit-mode row button + action bar | `Delete` in danger fill | `edit-delete-<id>` (exists) |
| **Move / file into a piece** | Edit-mode action bar → Move-to-piece sheet; drag as fast path | `Move to piece…` | `bar-move`, `move-target-<piece>` |
| Add to set list | Edit-mode action bar; arrangement sheet row | `Add to set list…` → existing `SetlistPicker` | `bar-setlists`, `chooser-<setlist>` (exists) |
| Remove from set list | inside the setlist's own list | visible `−` per member row | `setlist-remove-<slug>` |
| **Duplicate** | Edit-mode action bar; arrangement sheet row | `Duplicate` | `bar-duplicate` |
| New arrangement of a piece | piece row Edit button; arrangement sheet footer | `New arrangement` | `piece-new-arrangement-<id>` |
| Import into a piece | arrangement sheet footer; `+` menu | `Import into this piece` | `piece-import-<id>` |
| Reorder within a piece | drag (fast path) + `Move up` / `Move down` in the arrangement sheet row | buttons | `arr-up-<id>`, `arr-down-<id>` |
| New piece / set list, Import | `+` menu (§4) | two-item menu | `fab-new`, `fab-import` |

---

## 2. Library management without menus

### 2.1 Two modes, one rule
- **Browse** (default): rows open on tap. Trailing edge carries `ⓘ` (arrangement
  rows only) and the chevron. Nothing destructive is reachable here.
- **Edit** (the existing `Edit`/`Done` control): every row gains a **leading
  checkbox**, the row you last tapped shows its **labelled button row beneath
  it**, and any selection raises the **action bar**.

### 2.2 Action bar — `rev-2-library-edit-mode.png`
56pt, `panel`, 1pt top border, sits directly above the tab bar, `0 -6 18 / 7%`
shadow. Leading: `N selected` in mono. Then buttons in fixed order; destructive
last and right-aligned in `danger` fill. Actions that need exactly one row grey
to 42% rather than disappearing, so the bar never re-flows.

**The action set depends on what kind of thing is selected**, because the verbs
are not interchangeable:

| Segment / context | Selection | Bar |
|---|---|---|
| Pieces | pieces | `Rename` (1) · `New arrangement` (1) · `Delete N pieces` |
| Setlists | set lists | `Rename` (1) · `Delete N set lists` |
| Inside a set list | member arrangements | `Remove from set list` · `Move up`/`Move down` (1) |
| Arrangement sheet | arrangements | `Move to piece…` · `Add to set list…` · `Duplicate` · `Rename` (1) · `Delete N` |

A piece is a folder: it cannot be moved into a piece, duplicated, or put in a
set list. Those verbs belong to arrangements, one level down. Getting this wrong
was the first draft's mistake and it is worth stating in the code comments.

### 2.3 Move to piece — `rev-3-move-to-piece.png`
`PanelSheet`, 520pt. Band header naming what is moving. One row per piece with a
checkbox-style current marker, then a band `Or` with `New piece…` and `Remove
from piece` as rows. Primary `Move` bottom-right; `Cancel` in the header. Works
for one or many arrangements. This is the action that previously existed **only**
as a drag or a context-menu item — the single biggest hole this revision closes.

### 2.4 Set lists
Setlist rows in Edit mode get `Rename` / `Delete`. Inside a set list, each
member row gets a visible `−` (remove) and, in Edit mode, `Move up` / `Move
down` — the reorder that the legacy overlay's context menu carried.

---

## 3. The arrangement sheet is the arrangement management home — `rev-4`
Per-arrangement row: numeral, thumbnail, title, parts/versions, last change,
`Open`. Beneath the row, one line of 11.5pt buttons: `Versions` · `Set lists` ·
`Move to piece` · `Duplicate` · `Rename` · `Details` · `Delete`. Only the
selected/open arrangement's row shows them expanded, so three arrangements do
not produce twenty-one buttons.

Below the list: a `N arrangement(s) selected` band with the bulk bar, then a
`This piece` band with `New arrangement` (primary), `Import into this piece`,
`Rename piece`, and `Delete piece` right-aligned in danger. Piece-level verbs
are separated by a band header so `Delete` and `Delete piece` are never adjacent.

---

## 4. The `+` menu (item 8) — `rev-5-plus-menu.png`
Tapping the FAB opens a 250pt panel menu anchored above it; the FAB becomes `✕`
(`panel` fill, 1pt `clay`, `clayStrong` glyph) while open. Two 44pt rows:

| Row | Sub-label | Does |
|---|---|---|
| **New** | "A blank arrangement, filed under a new piece" | Pieces tab: name → create piece → `createArrangement`. Setlists tab the row reads **New set list** and its sub-label changes. |
| **Import** | "PDF, MusicXML, MIDI — a PDF goes through OMR" | the existing file importer; the result lands in Unfiled |

Tap outside or `✕` closes. `fab-new` / `fab-import` as ids; the existing
`library-add` id stays on the FAB itself.

---

## 5. Items 3 and 7 — `rev-1-library-browse-clean.png`
- **A–Z rail removed.** Delete `LibraryView.alphabetRail` (~`:321`), the
  `present` set, the `letter-<X>` scroll anchors and the `alphabet-rail`
  accessibility id. Sort still offers name / composer / changed / count, and
  search covers the "jump to L" case the rail served. This also gives the
  trailing edge back to the chevrons, which the rail was crowding on iPhone.
- **The count appears once, spelled out.** Drop the `.count` chips at
  `LibraryModel.swift:45` (pieces) and `:114` (set lists). The subtitle already
  reads `Stanley Myers · 3 arrangements` (`:59`) — set list subtitles gain the
  same wording: `4 arrangements · Cavatina #2 · Libertango #1 …`, truncated.
  `.warning` (OMR DRAFT) and `.plain` (UNFILED, 1 SOURCE) chips stay; they are
  facts you cannot read anywhere else on the row.

---

## 6. Paged canvas (item 2) — `rev-6`, `rev-7`

Today: one tall `ZoomableScroll` holding every page, zoom 0.5–12×, and a turn is
an animated scroll to a computed offset (`ScorePagesView:30`, `Score/PageTurn.swift:64`).

New: **the canvas shows exactly one page, or one spread when the spread setting
is on, and nothing else exists on screen.**

### 6.1 Layout
- The visible unit is an **index**: page `i` (spread off) or the pair
  `(i, i+1)` with `i` even (spread on). Stepping is ±1 / ±2.
- The unit is **fitted** to the canvas: `fit` = whole page(s) visible, both
  dimensions inside the viewport. That is zoom 1.0 by definition.
- **Zoom range becomes `1.0 … 12.0`.** Zooming out below fit is clamped — this
  is literally what "you can never see more than two pages" means. `0.5` goes.
- Pan exists only when zoomed past fit, and is **bounded to the current unit**:
  you cannot drag a neighbouring page into view. At fit there is no pan.
- Turning **changes the index and slides** the new unit in (220ms, the existing
  `Theme.Motion.overlay` spring): out to the left, in from the right, reversed
  for previous. It is no longer a scroll offset, so `scrollTarget` and
  `PageTurn.scrollTarget` computation are deleted.
- **Zoom persists across a turn; pan resets to the top-left of the new unit** —
  what a paper turn does. A violinist reading at 180% stays at 180%.
- The thumbnail strip sets the index directly (no offset arithmetic); the current
  unit's thumbs keep the 2pt `clay` outline, grouped by spread as today.

### 6.2 Gesture delta
The §6 arbitration table is unchanged for taps, Pencil and two-finger undo. Two
things change, one of them new:

| | Before | After |
|---|---|---|
| finger drag at fit | scrolled the stack | **nothing to pan** — so it is free to mean *swipe to turn* |
| finger drag, zoomed in | scrolled the stack, crossing pages | pans inside the unit, hard-stopped at its edges |
| swipe to turn | ambiguous against the scroll | **live only when there is no horizontal slack** (i.e. at fit, or at the horizontal limit while zoomed) |
| tap zones / strip / transport | turned | unchanged, always available |

**The one new ambiguity:** zoomed in, a horizontal drag that reaches the page's
edge could either stop dead or continue into a turn. Continuing is what
photo viewers do and it feels good; stopping is honest and never surprises. I
recommend **stopping** — a reader zoomed into a notehead does not want the page
to fly away — with turns still one tap away in the zones. Flag for Ali.

### 6.3 What this simplifies
- Selection addressing gets easier: the lasso is always inside one page's
  coordinate space, so `visibleRect` → page mapping in `ScorePagesView` and the
  `ScoreGeometry` join lose a whole class of edge case.
- `SpreadLayout` keeps `pageWidth`/`contentWidth` but loses the stack height.
- `DrawingStore` keys stay `slug/version/pN` — **no annotation migration**, and
  PencilKit still gets one canvas per visible page (now one or two, not N).

### 6.4 Risks
1. `ZoomableScroll` owns pinch anchoring and has been rebuilt three times
   (comments at `:23–42` are the scar tissue). Paging changes its content model
   again. This is the highest-risk edit in the revision and deserves its own
   branch and its own tests before anything else lands on it.
2. Fit-to-page on a 12-page score with a tall page means small notation; the
   `Fit width / Fit page` control in `… → Score display` becomes load-bearing
   rather than cosmetic. Recommend defaulting to **fit page** on iPad landscape
   with the spread off, and **fit width** on iPhone.
3. Rapid turning while a slide animation is in flight — coalesce to the latest
   index rather than queueing animations.
4. Any UI test that scrolls the canvas to find a page breaks; page presence is
   now an index assertion.

---

## 7. Test churn (expect it)

Removed ids: `alphabet-rail`, everything reaching a feature through
`.contextMenu`, and whatever drove the legacy overlay's rows.
New ids: `bar-move`, `bar-setlists`, `bar-duplicate`, `bar-rename`,
`bar-delete`, `move-target-<piece>`, `fab-new`, `fab-import`,
`setlist-remove-<slug>`, `arr-up-<id>`, `arr-down-<id>`,
`row-select-<id>` (the checkbox), `library-actionbar`.
Kept: `row-<id>`, `edit-versions-<id>`, `edit-rename-<id>`, `edit-delete-<id>`,
`chooser-<setlist>`, `library-add`.

Ali's rule from `CLAUDE.md` applies: preserve the existing tests, update them
where behaviour intentionally changed, never weaken them to reach green.

---

## 8. Build order

1. **Edit mode: checkboxes + action bar** on Pieces and Setlists, with Rename
   and Delete only. Nothing removed yet.
2. **Move to piece sheet** + `Duplicate`, wired to the existing
   `assignToPiece` / `duplicateScore`.
3. **Arrangement sheet buttons** + its bulk bar + reorder buttons.
4. **`+` menu.** Small and independent.
5. **Delete all six context menus**, the legacy overlay in `ContentView`, the
   pill's library button and `classicManager`. Only now, when every action has
   its new home.
6. **Rail out, count chips out.** Trivial, separate commit.
7. **Paged canvas**, on its own branch, tests first: index stepping, zoom clamp
   at fit, pan bounds, spread parity, strip jump, slide coalescing.

Steps 1–6 are additive or subtractive with no shared state; step 7 touches the
canvas alone. Nothing here needs the engine or the score model, so it will not
collide with model-layer work.
