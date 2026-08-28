# 0.4.2 — modal-free management, per-row hamburger

Supersedes the sheet-based parts of `NAV_REVISION_0.4.1.md`. Design only; no app
code changed. Mockups: `scoranger-modal-free.html`, `png/mf-*.png`.

Five directives:

1. **Nothing floats.** No sheets, popovers, alerts, action sheets or menus. Every
   destination is a screen; every choice happens in place.
2. **One control per row.** Per-row actions live behind a single visible `☰`, and
   tapping it opens a screen or expands the row — never a popup, never a long press.
3. **Simplify: the value is the control.** Where an action's only job is to edit
   a value, delete the action and make the value itself tap-to-edit in place.
   Rename is the worked example: there is no Rename row anywhere any more — you
   tap the name. This is a **standing principle for all future work**, not a
   one-off: before adding a button, ask whether the thing it would change could
   simply be tapped.
4. **No drag-and-drop.** Nothing in the app is filed, ordered or moved by
   dragging. Filing happens at import or through *Move to piece*; membership
   through the set list's *Add arrangements*; order through *Move up* / *Move
   down*. Also standing: a feature whose only affordance is a drag has no
   affordance at all — it is invisible to Switch Control, undiscoverable without
   being told, and impossible to state in a test as anything but coordinates.
5. **One place, not two.** Home is removed and merged into My Library. A screen
   that only points at other screens earns its keep only while there is
   something to point at; with one library and no sharing, Home was a lobby in
   front of the room people actually wanted. Also standing: prefer one screen
   carrying its own actions over a second screen that launches them.

Carried forward unchanged from 0.4.1: paged canvas, A–Z rail removed, count
spelled once, `+` offering New and Import.

---

## 1. The pattern rule

| Pattern | Used for | Never |
|---|---|---|
| ~~**Tab**~~ | *removed with Home (§4C)* — the app has one place | — |
| **Push** (nav bar with a back label) | anything about an existing object; every option tree; every picker with a list of targets | trivial two-way choices |
| **Inline reveal** — content expands in place, nothing dims, nothing to dismiss | creating (the `+` band), editing a value in place, confirming a delete, the score's title switcher, order-only row actions | anything with more than ~5 rows |
| **Anchored bar** (bottom, above the tab bar) | multi-select actions, undo | anything that blocks the list behind it |
| **Tap-to-edit** — the value becomes a field where it sits | every editable value: names, composer, keys, hostnames, the model alias | values on a row whose tap already opens something (§4A) |
| **Drag-and-drop** | *nothing* | filing, ordering, membership, reparenting — all of it is buttons and screens now (§4B) |
| **Drag to reposition a floating control** | the ink bar's handle, and nothing else (§4B.1) | reaching any feature |
| **Compact action row** — small bordered buttons in the screen's control bar | the four library-level actions (§4C) | anything about one row; that is `☰` |

A bar is not a modal: it is anchored, blocks nothing, and the content scrolls
behind it. That is why Edit mode's multi-select bar survives.

**System pickers stay system.** `UIDocumentPicker` (Import), `ShareLink`, the
keyboard and the OS colour picker are Apple's modals; we do not reimplement
them. Everything we own is a screen.

---

## 2. Every floating surface today, and its replacement

Swept from the 0.4.0 tree. There are no `.sheet`/`.alert` calls — the app builds
its own floating panels — so the sweep is by construct, not by API.

| Floating today | File | Becomes |
|---|---|---|
| `RowContextMenu` (long press) | `LibraryManagement.swift:16` | Deleted. `☰` → the item's screen (§3) |
| `LRow`'s `contextMenu { menu() }` | `TabBar.swift:148` | Deleted with its `Menu` generic; `LRow` gains a trailing `☰` slot |
| Arrangement row menu in the sheet | `LibraryManagement.swift:103,179` | Arrangement screen (§3.2) |
| Legacy sidebar menus (3) | `ContentView.swift:796, 858, 1002` | Set list screen + Edit mode; the legacy overlay itself is deleted |
| `ArrangementSheet` + `DialogScrim` | `LibraryManagement.swift:108`, `RootView.swift:75` | **Piece screen** (§3.1) |
| `MoveToPieceSheet` | `RootView` `managementSheets` | **Move to piece screen** (§3.3) |
| `SetlistPicker` | `LibraryManagement.swift:58` | **Set lists screen** (§3.4) |
| `SetlistArrangementPicker` | `LibraryManagement.swift:247` | **Add arrangements screen**, pushed from the set list |
| `ScoreInfoView` in a `PanelSheet` | `RootView` | **Details screen**, pushed from the arrangement screen |
| Settings in a `PanelSheet` | `RootView:80` | **Settings screen**, pushed from Home (§6) |
| `PanelAlert` — rename | `RootView` | inline field in the row (§5.1) |
| `PanelAlert` — create piece / set list | `RootView` | inline field in the `+` band (§5.1) |
| `PanelAlert` — delete one / delete many | `RootView` | inline confirm strip + undo bar (§5.2) |
| `PanelNotice` / `state.notice` | `PanelDialogs.swift:78` | inline banner at the top of the current screen |
| `TitleMenu` (score) | `ContentView.swift:193` | inline switcher band (§7.1) |
| `MoreMenu` (score) | `ContentView.swift:214` | **Options screen**, two layers (§7.2) |
| Pill's version and options `Menu`s | `DesignSystem/Pill.swift:37,58` | deleted with the pill's score-view role |
| Chat model `Menu` | `ContentView.swift:529` | **Chat model screen**, pushed from the chat header |
| `ScoreInfoView`'s part `Menu` | `ScoreInfoView.swift:216` | inline reveal on the part row |

`PanelSheet`, `PanelAlert`, `PanelNotice` and `DialogScrim` all leave the design
system. `BandHeader`, `SheetRow`, `PanelToggle`, `PanelField`, `WellBlock`,
`PanelButton`, `LED` and `StateView` stay — they are now screen furniture.

---

## 3. The screens

### 3.1 Piece screen — `mf-02-piece-screen.png`
Pushed from a piece row's `☰` (and from tapping a piece with more than one
arrangement). Nav bar: `‹ My library` · title. Head: name, composer, counts,
last change in mono. Then `ARRANGEMENTS — TAP TO OPEN` (each row with its own
`☰`), `THIS PIECE` (New arrangement, Import into this piece, Rename piece),
`SOURCES` (read-only), and Delete piece last, in danger.

### 3.2 Arrangement screen — `mf-03-arrangement-screen.png`
Pushed from an arrangement row's `☰`. **This is the per-item actions screen.**
Nav bar carries `Open` as the primary button, so reading is still one tap from
here. Rows are grouped by intent:

- **Do** — Move to piece ›, Set lists ›, Duplicate  *(no Rename: the head title is the control)*
- **Look at** — Versions ›, Parts and ranges ›, Details ›
- **Careful** — Delete arrangement (two-step, §5.2)

Trailing values state the current answer (`Cavatina`, `1 of 3`, `14`) so the
screen reads as a summary as well as a menu.

### 3.3 Move to piece — `mf-04-move-to-piece-screen.png`
Pushed. Piece rows with the current one ticked; a band `Or` with **New piece**
(reveals a field inline, `Create & move`) and **Remove from piece**. A banner
states the renumbering consequence. Works for one arrangement or a selection.

### 3.4 Set lists — `mf-05-setlists-screen.png`
Pushed. Membership checkboxes commit on tap — nothing to confirm, nothing to
dismiss. `New set list` reveals its field inline.

### 3.5 Set list screen — `mf-06-setlist-inline-reveal.png`
Pushed from a set list row. Nav bar: `Reorder`, `Play from the top`. The head carries the
set list's name, tap-to-edit. Members numbered in order, each with `☰`. Here `☰` **expands in place** rather than
pushing, because every action is one tap and order-related: Move up, Move down,
Open its arrangement screen ›, Remove from this set list. One row open at a time.
No Rename here either — a member's name belongs to its arrangement, and that is
edited on the arrangement screen.

**Why two behaviours for `☰`:** pushing is right when the actions need a target
list or lead to more detail; expanding is right when they are immediate and
positional. The rule for the engineer: *if any action on the row needs a second
screen, `☰` pushes; if they are all one tap, `☰` expands.*

### 3.6 Versions, Parts, Details
Pushed lists from the arrangement screen. Versions replaces the old version menu
and the sheet's nested list; tapping a version displays it and returns.

---

## 4. The library list — `mf-01-library-row-hamburger.png`
Unchanged from 0.4.1 except: every row now ends in `☰`; no `N ARR` chip; no A–Z
rail. Row tap = open the music (a piece with several arrangements pushes the
piece screen). `☰` = manage. Edit mode still adds checkboxes and the bar for
bulk work; per-row buttons are gone — that is what `☰` replaced.

---

## 4A. Tap-to-edit: every value, and where it lives

*The third directive, applied across the whole design.*

The conflict to resolve is simple: **a library row's tap opens the music**, so
the name is not editable there. Editing lives wherever the value is *displayed as
the subject of the screen*, not wherever it is listed.

| Value | Editable on | Not editable on | Engine call |
|---|---|---|---|
| Piece name | Piece screen head | library rows, Home recents, set list member rows | `renamePiece` |
| Composer | Piece screen head (sub-line) | anywhere it is listed | `setScoreMetadata` |
| Arrangement name | Arrangement screen head; the score's title-switcher band | library rows, piece screen's arrangement rows, set list rows | `renameScore` |
| Set list name | Set list screen head | library rows | `renameSetlist` |
| Part name | Parts and ranges screen, on the part row | score canvas | `renamePart` |
| Title / composer / arranger of the notation | Details screen rows | — | `setScoreMetadata` |
| Chat model alias | Settings row and the chat header — tap the value, options reveal inline | — | client only |
| OpenRouter key, OMR key, Mac address | Settings rows | — | client only |
| Slug | Details screen, with the two-step confirm strip (§5.2) because it moves files | — | `renameSlug` |
| Zoom, fit, accidentals, spread, fingerings | already direct controls — stepper, segmented, toggle | — | — |

**Rows this deletes** (the whole point):

| Deleted | Was on |
|---|---|
| `Rename` | arrangement screen · row hamburger reveal |
| `Rename piece` | piece screen |
| `Rename set list` | set list screen |
| `Rename` in the multi-select bar | Edit mode — bulk-renaming two things was never meaningful |
| `Chat model ›` | Settings (a pushed screen for one alias) |
| `OpenRouter key ›`, `Mac address ›` | Settings |

### The affordance
A tappable value carries **a dashed underline and a small clay pencil** —
always, because iPad has no hover. Tapping puts a field in its place with the
caret at the end, `Save` and `Cancel` beside it. It **commits on leaving the
field or the screen**; an empty value reverts to the old one, so there is nothing
to confirm and no way to lose a name. A value whose options are a fixed set (the
model alias) shows a chevron instead of a pencil and reveals its options inline.

### Discoverability and accessibility — the honest costs

| Risk | Mitigation |
|---|---|
| A tappable title looks like static text | The dashed underline + pencil is permanent, not a hover state. It is the only place in the system that uses a dashed underline, so it means exactly one thing. |
| The word "Rename" disappears from the UI, and with it the way people search for it | A one-time `hintband` on the first visit to a detail screen: *"Anything with a dashed underline is editable — tap it."* Dismissible, inline, shown once per install. |
| VoiceOver users lose a labelled button | Each value is a real `Button` (not a `Text`), labelled *"Piece name, Cavatina"* with the hint *"Double tap to edit"*. Switch Control and full keyboard access reach it exactly as they reached the old row. |
| Accidental edits from a stray tap | Entering edit mode changes nothing until you type; `Cancel` and empty-reverts make it a no-op. |
| Tap-to-edit steals long-press-to-select-and-copy on those labels | Accepted. Copying a piece name is rare; the field itself supports selection once open. |
| Two meanings for a tap on the score's title (open the band vs. edit the name) | The top bar's title opens the band; the name **inside** the band is what edits. One tap target each, never nested. |

## 4B. Filing, order and membership without dragging

*The fourth directive. Everything dragging used to do, and what does it now.*

| Dragging used to | Now |
|---|---|
| drop an arrangement on a piece heading to file it | **at import**: the `ImportDestinationScreen` asks *Where should it go?* — `New piece` (named inline) or one of the existing pieces, before the file is ingested. For anything already unfiled: arrangement `☰` → **Move to piece** |
| drop an arrangement on another to reorder it inside a piece | **Move up / Move down** on the piece screen's arrangement rows, which renumbers `#N` live |
| drop an arrangement on a set list heading to add it | the set list's **`+` Add arrangements** screen |
| drop a member out of a set list | **Remove from this set list** in the member row's `☰` reveal |
| drop onto the Unfiled band to unfile | **Remove from piece** on the *Move to piece* screen |
| reorder set list members | **Move up / Move down** on the member rows |

### The order control
`▲` / `▼` sit on the row itself, always visible, on **rows that have an order** —
the piece screen's arrangements and a set list's members. They are 32pt icon
buttons, disabled and dimmed at the ends of the list, each with a spoken label
(*"Move Accordion duo up"*). Library rows never get them: a sorted list has no
order to change.

Two consequences worth stating:

- **`#N` renumbers as you tap**, because `#N` *is* the position. That is the
  feedback; no confirmation, nothing to save.
- The set list screen's nav-bar `Reorder` button and the `Move up`/`Move down`
  rows inside the member `☰` reveal both **go away** — with `▲▼` on the row there
  is exactly one way to reorder, and it is the shortest one. The reveal keeps
  `Open its arrangement screen ›` and `Remove from this set list`.

This is three controls on an ordered row (`▲`, `▼`, `☰`) against the one-control
rule in directive 2. Deliberate: reordering is the most-used management action at
a gig, ordered rows are a minority of rows, and hiding `▲▼` behind a mode costs a
tap on every single move. If Ali would rather have the calm row, the alternative
is a `Reorder` toggle in the nav bar that reveals `▲▼` — same mechanism, one more
tap, fewer glyphs at rest.

### First feature designed under this rule
Element repositioning and resizing — chord symbols first — is specified in
`docs/size-and-position-spec.md` §"Interaction — no drag, no modal": the
selection chip gains a position pad and a size ladder, taps accumulate as a
pending adjustment, and the op commits when you leave the element. It is the
worked example of replacing a drag with buttons without losing the feature.

### What is *not* affected
The rule is about drag-and-*drop* — moving objects. Continuous gestures that
manipulate the view or draw are untouched: finger pan and pinch on the score, the
Pencil lasso, PencilKit ink, and the swipe-to-turn described in the paged-canvas
spec. One genuine judgement call: the **chat pane's draggable divider**
(`ChatView.swift:206`) is a resize, not a drop target. Keeping it is consistent
with the rule as written; if Ali wants literally no dragging, it becomes a
two-width toggle in the chat header. Flagged, not decided.

## 4C. Home is gone; My Library is the app

*The fifth directive.* The tab bar held Home, My Library, and a disabled Shared
placeholder. Home held a search field, four large action panels, recent pieces
and recent set lists. All of it goes, and what survives moves into My Library.

### What is removed

| Removed | Why | What replaces it |
|---|---|---|
| The Home screen | A lobby in front of the library | My Library is the app's root |
| `RECENT PIECES` / `RECENT SETLISTS` sections and their `All … ›` links | The library **is** the list; recency is a sort, not a section | `Sort: recently changed` in the library's control bar |
| The four large coloured panels | Two thirds of the screen for four occasional actions | the compact action row below |
| The bottom tab bar | One live tab and one disabled placeholder is not a tab bar | nothing — the app opens on My Library; the `Pieces / Setlists` segmented control is the only place-switcher |
| The `+` FAB and its New/Import band | It offered exactly what the action row now shows permanently | the action row (this is the de-duplication) |
| The Home build stamp | Screen furniture with no home | `Settings → About` |

`RecentSetlists` (the `UserDefaults` list) shrinks to a single
`lastOpenedArrangement`, which is all **Ask** needs.

### The compact action row — exact placement and size

One bar, two clusters, directly **below the search field and above the list**.
The library-level actions sit left; the list controls sit right, where they
already are:

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ?   ✉²   ⚙                                          ● on-device         │  44pt
│  My Library            7 pieces · 9 arrangements                         │
│  ⌕ Search in my library                                                  │  40pt
│  ⤓ Import   ▢ New   ☰ New set list   ⌸ Ask        ⇅ Sort: name  ⌗ Filter  Edit │  44pt
│ ─────────────────────────────────────────────────────────────────────── │
│  rows…                                                                   │
└──────────────────────────────────────────────────────────────────────────┘
```

| Property | Value |
|---|---|
| Row height | **44pt** (32pt controls + 6pt above and below) |
| Side padding | **20pt**, matching the list rows so the buttons line up with the thumbnails |
| Button | 32pt tall, 1pt `line2` border, radius 2 (`rCtl`), `panel` fill, 10pt horizontal padding, 13pt/600 label after a 13pt SF Symbol |
| Gap within a cluster | **8pt** |
| Gap between the clusters | **16pt minimum**, a `Spacer(minLength: 16)` between them |
| Order, left cluster | Import · New · New set list · Ask — the panels' old order |
| Order, right cluster | Sort (shows its value) · Filter · Edit |
| Space above / below | 12pt from the search field, **16pt** to the first row or band |
| Compact width (< 700pt) | the left cluster drops its labels to 32×32 icon buttons, same order and identifiers; `Sort` keeps its value, `Filter` and `Edit` become icons |
| Emphasis | none. `Import` is **not** tinted: at four buttons in a bar, a clay fill would shout. The accent stays for selection and `#N` |

Identifiers move with the actions: `library-import`, `library-new`,
`library-new-setlist`, `library-ask` (retiring `home-import`,
`home-new-arrangement`, `home-new-setlist`, `home-ask`, and `library-add`).

### What moves to the library's top row
The help, inbox (with its count) and settings icons, and the engine chip, all
keep their Home positions — leading trio, chip trailing — now on My Library.
The chip prints the mode **once**: `LED` becomes a dot with no label of its own.

### Behaviour after the merge
- The app launches on My Library, on the segment last used.
- **Ask** opens the last-opened arrangement with the chat panel open; with
  nothing opened yet it is disabled rather than hidden, so the row never
  re-flows.
- The score view still presents over the library and `✕` always returns to it —
  `cameFrom` and its two cases go away.
- **Empty library** is now the app's first screen, so it carries the welcome:
  the action row stays visible above the empty state, and the state reads
  *"Nothing here yet — import a score, or make a blank arrangement and ask for
  what you want."*
- When sharing lands, the second place returns as a third segment
  (`Pieces / Setlists / Shared`), not as a resurrected tab bar.

### 4B.1 The one drag left, and why it is allowed

The ink bar carries a move handle (`✥`, labelled "Move the ink tools"). It is
the only drag in the app and it stays, by Ali's own request in the 0.4.4 batch:
the tools dock in the footer, and the handle moves them off whatever they are
covering.

It does not break §4B, which is about features that can only be REACHED by
dragging. Every tool on the bar is reachable where it sits; the drag only
changes where the bar is. And a TAP on the handle re-docks it, so the drag is
never the only way back — that is the rule §4B actually protects.

Recorded here because the QA sweep read it as an unexplained glyph (L24). If
Ali would rather it went, removing it is a five-line change and the bar simply
stays docked.

## 5. Inline patterns — `mf-07-inline-patterns.png`

### 5.1 Creating and editing
- **Editing** never has a button: tap the value (§4A). The keyboard is the only
  thing that overlays, and that is the OS.
- **Creating** is the same gesture one step earlier: `+` reveals a two-row band
  at the top of the list (`New piece` / `New set list`, and `Import`) and the
  name is typed in the band, where the thing will live. No popup, no pushed
  screen for two choices.

### 5.2 Destructive actions without a dialog — the awkward case, solved
Two steps, then reversible:

1. Tapping `Delete …` turns the row into a **confirm strip** on an error-tinted
   ground: `⚠ Delete Blue Bossa and its 2 versions?` with `Delete` (danger) and
   `Keep`. It states *what* will go, which an alert usually does not.
2. On confirm, the row goes and an **undo bar** appears in the action bar's slot:
   `Deleted Blue Bossa. · restorable for 10s · Undo`.

Undo needs the engine to keep the artifacts for the window instead of unlinking
at once — `deleteScore`/`deleteSetlist` become a two-phase delete (mark, then
sweep). **This is the one piece of new engine work this revision needs.** If Ali
would rather not have it, the fallback is the two-step confirm alone, with no
undo; the strip is honest enough on its own, and that is a one-line change.

### 5.3 Notices and errors
`state.notice` and render failures become a banner strip at the top of the
current screen with a `✕`. They never block, and they never appear over the score.

---

## 6. Settings — `mf-10-settings-screens.png`
Pushed from Home's gear. Rows: Engine, PDF conversion, Chat model, Score display,
Annotations, About. Rows whose content is a *value* (model alias, keys, hostname)
do not push at all any more — the value is tapped in place; only the genuine
sub-trees push. On iPad the second layer opens
beside the first (two columns); on iPhone it pushes. Same shape as the score's
Options screen, so there is one settings idiom in the app, not two.

---

## 7. The score view

The score view itself is a full-screen place with `✕`, not a modal — it stays.
Its two floating panels do not.

### 7.1 Title switcher — `mf-09-title-switcher-band.png`
Tapping the title opens an **inline band** below the top bar: arrangements of
this piece on the left, versions of the open one on the right, `All 14 versions
›` pushing the full list. The band's first row shows the open arrangement's name
**tap-to-edit** — that is where renaming lives in the score view. The band pushes the score down; the paged canvas
simply fits into less height, which is the one real advantage of paging here —
there is no scroll offset to preserve. Tap the title again to close.

### 7.2 Options — `mf-08-score-options-screens.png`
The `…` popover becomes a pushed screen with the same nine categories and the
same second layer. `✕`/back returns to the score with its page and zoom intact.

### 7.3 What is *not* a modal here
The chat pane, the ink bar, the thumbnail strip and the transport are docked
chrome: anchored, non-blocking, no dismissal required. They stay. The chat
header's model `Menu` becomes a pushed screen.

---

## 8. Risks and awkward corners

1. **Depth.** Reaching "move this arrangement to another piece" is now Library →
   piece `☰` → arrangement `☰` → Move to piece — three pushes. Mitigations in
   the design: filing is normally answered **once, at import** (§4B), so the deep
   path is only for re-filing; the arrangement screen states current answers so
   you rarely need to go deeper; `Open` sits in the nav bar; and the `☰` on
   arrangement rows inside the piece screen pushes straight to the arrangement
   screen, which is where Move lives. Dragging is no longer the escape hatch it
   used to be, so this path has to stay short on its own merits.
2. **Undo needs engine support** (§5.2). Flagged as the only backend change.
3. **The keyboard is unavoidable** for rename and naming; an inline field near
   the bottom of a list will be covered. Scroll the focused row above the
   keyboard on focus.
4. **Two `☰` behaviours** could read as inconsistent. The rule in §3.5 is
   testable, and the icon state differs: expanded rows show `☰` lit, pushed rows
   do not.
5. **Test churn, again.** Everything that drove a sheet or alert changes shape:
   new ids `row-menu-<id>`, `screen-piece-<slug>`, `screen-arrangement-<slug>`,
   `move-target-<piece>`, `inline-rename-field`, `confirm-delete-<id>`,
   `undo-delete`, `add-band-new`, `add-band-import`, `title-switcher`,
   `score-options`. Retired: every `chooser-*` sheet id, `sheet-done`, the alert
   ids.
6. **Fewer buttons means fewer nouns to hunt for.** Tap-to-edit is the right
   default, but it moves discovery from reading a list of verbs to noticing an
   affordance. The dashed-underline convention plus the one-time hint band is the
   mitigation; if Ali sees anyone miss it, the cheap fallback is a pencil button
   in the nav bar of detail screens that focuses the title field — one button, not
   a row per value.
7. **Removing drag is a net accessibility gain, not a cost.** Nothing that used
   to require a drag now requires one, so Switch Control, full keyboard access
   and VoiceOver reach every filing and ordering action for the first time. The
   only thing lost is speed for people who liked the gesture; `▲▼` on the row is
   one tap, which is close.
8. **Back-button semantics on iPad.** With no `NavigationStack` in the app today,
   this introduces one per tab. The score view must stay outside the stacks —
   it is presented over them, as now.

---

## 9. Build order

1. `NavigationStack` per tab, plus the nav bar component. Nothing moves yet.
2. Piece screen and arrangement screen; row `☰` pushes to them. Sheets stay
   reachable in parallel so nothing breaks mid-flight.
3. Move to piece, Set lists, Add arrangements, Versions, Parts, Details screens.
4. Inline rename, `+` band, two-step delete, undo bar (engine two-phase delete
   behind a flag; ship the two-step confirm first).
5. Set list screen with inline reveal.
6. Score: options screen, title switcher band, chat model screen.
7. Settings screen and its sub-screens.
8. **Delete** `PanelSheet`, `PanelAlert`, `PanelNotice`, `DialogScrim`,
   `RowContextMenu`, `LRow`'s menu generic, the legacy overlay, the pill's
   score-view role, every `Menu` listed in §2, and **every drag path**:
   `ContentView`'s `dropDestination` (`:620`), `DropTarget`, `DropHighlight`,
   `RowDrop`, `acceptsArrangementDrop`, `LibraryView`'s `.draggable`, and the
   `beginLift`/`endLift`/`lifted` state. `AppState.placeInPiece(before:)` exists
   only to serve drop-at-a-position and becomes unused — delete it; `Move up` /
   `Move down` go through `reorderPiece`. A grep for
   `contextMenu|PanelAlert|PanelSheet|DialogScrim|Menu {` should return nothing
   outside the design system's own removed files; a grep for `"Rename` should
   return nothing outside `EditableValue`'s accessibility labels; and a grep for
   `draggable|dropDestination|onDrag|onDrop|DropTarget` should return only
   `ChatView`'s divider (or nothing, if that becomes a toggle). Those three greps
   are the acceptance test.
