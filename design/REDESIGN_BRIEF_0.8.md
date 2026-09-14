# Scoranger 0.8 redesign brief

Input for a Claude Design session. Written 2026-09-10 from the owner's words,
against the app as it is on 0.7.4 build 191. Everything in §1 is the owner's
ask; §2–§4 are the grounding a design pass needs and usually does not get.

## 1. The ask, in the owner's words

> The UI is not quite what I want; it's too square; there are too many sharp
> edges. The titles of many of the settings are weird AI-slop phrases instead
> of one or two words labelling a UI element like normal. I like the colour
> scheme but there are many weird inconsistencies and ugly things in the
> settings menus. There is generally too much white space when some menus open
> and take up half the screen. The way that many button clicks result in a
> full-screen-width dropdown that pushes the rest of the UI down is very
> awkward. I want the UI to be more welcoming and friendly — warm and cosy.
> Always clear what you are doing. Lots of attention to detail of alignment
> and UI element centring. I also want the UI to be more distinctive and less
> generic, with sass and uniqueness. Deep consideration of consistency across
> menus, settings and options; the way modals are used — I'm generally
> anti-modal / anti-popup and would prefer permanent homes for things like the
> play transport and mixer, which can go at the bottom and, in performance
> mode, be hidable with a subtle button.

### The deliverable

**Five competing options**, each presented across **the same ten screens and
workflow steps** (§3), so they can be compared like for like. For each option:
a one-paragraph stance, the ten screens, and a components sheet showing how
its rules produce them. One of the ten must be a *sequence* (a workflow, not a
screen), so the transitions and the "always clear what you are doing" claim
can be judged.

### What must survive

- **The colour scheme.** Paper, ink, one clay accent (§2.1). The owner likes it.
- **Score first.** The score is the ground; everything else is over or beside it.
- **The arrangement numeral** (`#1`) as the app's identity mark.
- **No login gate.** Sharing needs an account; nothing else does.
- **Accessibility.** 44pt hit targets, Dynamic Type through AX3, VoiceOver
  labels on every control. The current system honours these; a redesign that
  does not is not a candidate.

### What is explicitly up for grabs

- **Corner radii, edges, weight.** "Instrument panel" chose 2–3pt corners and
  hard 1pt edges (§2.2). The owner now calls that too square. Rounder, softer,
  warmer is the direction; how far is the design's call, per option.
- **Every label.** One or two ordinary words, the way a settings screen
  normally reads (§4 lists the current ones).
- **Every disclosure.** Full-width bands that expand in place and push the
  page down (the current "no modal" answer) are the thing the owner finds
  awkward. Anti-modal still stands — so the options need a *third* way.
- **Where the transport and mixer live.** Permanent home at the bottom; in
  performance mode, hidden behind a subtle affordance.
- **Empty space.** Menus that open to half a screen for three rows.

## 2. What exists today

### 2.1 Tokens (`ios/Scoranger/DesignSystem/Theme.swift`, `design/DESIGN_SYSTEM.md`)

Surfaces: paper `#FFFFFF` (the score page, the only pure white), ground
`#F4F0E8`, panel `#FAF7F1`, well `#EFEAE0`, band `#F1ECE2`. Ink: `#1A1917`,
`#6B655C`, `#8A8378`. One accent: clay, with a `clayStrong` for small text.
Light only, by decision.

Type: Space Grotesk for titles and numerals, Inter for prose, IBM Plex Mono for
machine values. A compressed, weight-driven ladder, 10–34pt.

### 2.2 The current direction, and where it grates

*"A warm paper-and-clay instrument panel, score-first, with the arrangement
numeral as the app's identity."* Flat fills, hard 1pt edges, 2–3pt corners,
silkscreen band headers (tracked-out caps), chunky square toggles, the engine
state as a real LED.

The owner's complaint maps onto this precisely: the instrument-panel metaphor
delivered squareness and hard edges as a *feature*. The warmth is in the
palette and not yet in the forms. The band headers read as machine labels
rather than as a welcome.

### 2.3 Documents worth reading before designing

- `design/DESIGN_SYSTEM.md` — the spec as approved; the components list (§7)
  is the inventory to redesign.
- `design/NAVIGATION_SYSTEM.md`, `design/NAV_MODAL_FREE_0.4.2.md` — why there
  are no modals and what replaced them (the in-place bands the owner now
  finds awkward). The reasoning holds; the form does not.
- `design/MIXER_WINDOW.md` — the mixer as a floating window you can pick up.
  The owner now wants it parked at the bottom instead.
- `design/PLAYBACK.md`, `design/CONTINUOUS_VIEW.md` — the transport and the
  scroll-mode strip, including the follow rule (line parked a quarter in).
- `design/IPHONE_0.6.14.md` — the phone layout and its metrics rules.
- `design/FIREBASE.md` §6A — sharing as a field on a set list: one kind of set
  list, a share button on its row, a two-people glyph once shared.

### 2.4 Photographs of the app as it stands

`ScorangerUITests/DesignerSweep` photographs every screen at several widths and
Dynamic Type sizes. Run it once and hand the folder to the design session:

    cd ios && TEST_RUNNER_SCORANGER_SHOT_DIR=/path/to/shots \
      xcodebuild test -project Scoranger.xcodeproj -scheme Scoranger \
      -destination "platform=iOS Simulator,name=iPad Pro 11-inch (M4)" \
      -only-testing:ScorangerUITests/DesignerSweep

Draw the five options against these, not against memory.

## 3. The ten screens and steps

Chosen to cover every surface and every kind of interaction, and to include
the places the owner named.

| # | Screen or step | Why it is in the ten |
|---|---|---|
| 1 | **Library — Pieces** (list, search, sort/filter, edit) | The home. Full-width rows, the numeral, the bands. |
| 2 | **Library — Set lists** with a shared row | The share glyph, the two-people glyph, the `+`, the `☰`. |
| 3 | **A set list's own screen** | Running order, rename-in-place, people, leave/delete. Half-screen disclosures live here. |
| 4 | **Score, reading, paged** | The permanent ground. Top bar, page chip, thumbnails rail. |
| 5 | **Score, playing, scroll mode** with the transport and mixer | The owner's stated home for both: bottom, permanent, hidable in performance. |
| 6 | **Performance mode** | Everything hidden but the score; the subtle way back. |
| 7 | **Settings** and one section (Account) | The labels, the whitespace, the sign-in. |
| 8 | **The arrangement `☰` screen** (versions, parts, details) | Deep disclosure; the current expand-in-place pattern at its worst. |
| 9 | **Sequence: share a set list** — tap share → progress → share sheet → recipient taps link → "Add to my set lists" → row appears | The workflow; "always clear what you are doing". |
| 10 | **Sequence: import a PDF and open it** — Import → progress → the scan opens → OMR offered | The other workflow; progress and state. |

Each option shows all ten at iPad width; options may add a phone variant of
1, 4 and 5 where the answer differs.

## 4. The labels as they stand

Every band header, row and button title currently shown in settings and the
management screens, verbatim, so the rewrite has the real list. The owner's
rule: one or two words, the way a settings screen normally reads.

**Settings:** Account · Send my address · Sign out · "Signing out keeps your
library on this iPad. Nothing is deleted." · Paste an invitation · Reading ·
Titles · About · Diagnostics · On-device engine · Remote engine · PDF
conversion (OMR) · Chat model · Save · Clear

**Piece and set list screens:** Pieces · Or · New piece · Remove from piece ·
In these set lists · New set list · Play from the top · Running order · This set
list · Add arrangements · People in this set list · In this set list · History ·
Parts · "No parts recorded for this version."

Some of these are fine. The ones the owner means are the sentences, the "Or",
and the headers that describe rather than name.

## 5. Constraints on the options

- **Anti-modal is a principle, not a style.** No sheets or popups as the
  primary pattern. But in-place expansion that shoves the page is out too.
  Each option must state its disclosure pattern in one sentence.
- **The transport and the mixer have a home**, at the bottom, together or
  adjacent; performance mode hides them behind one subtle control.
- **Alignment and centring are first-class.** Every option's components sheet
  states its grid and its rule for centring a label in a control.
- **Warm and cosy, distinctive, with sass.** Not generic iOS, not a Material
  clone, not the current instrument panel. Five genuinely different stances.
- **Everything in the ten screens is real.** No invented features; every
  control shown exists today or is in `design/FIREBASE.md`'s 0.7 plan.

## 6. What to hand back

For each of the five options: the stance, the ten screens, the components
sheet, and a short note on what it would cost to build against the current
SwiftUI code (which components change shape, which change only tokens). The
owner picks one, or a combination; then `design/DESIGN_SYSTEM.md` is rewritten
as the spec for 0.8 and the tokens in `Theme.swift` follow it.

---

# 7. Two fixes from build 193 testing (2026-09-11)

## 7.1 Inline creation: why it looks messy

`InlineRenameRow` (`Navigation/Screen.swift:213`) puts a text field and two
buttons in one `HStack`. Four measurable faults, all visible at once:

| Fault | Numbers |
|---|---|
| Field and buttons are different heights | field is `.typeRole(.body)` (Inter 13, line height 15.7) plus 7pt padding each side = **29.7pt**; `PanelButton` is `.frame(minHeight: 34)`. The `HStack` centres them, so neither edge lines up |
| The row is shorter than its neighbours | 8 + 34 + 8 = **50pt** against `LibraryRow`'s `minHeight: 56`. A 6pt jog in the list rhythm |
| Save hangs past the `☰` column | the row uses `.padding(.horizontal, s20)`; rows with a menu reserve `rowMenuInset` = 60, and set list rows now reserve `rowTwoControlInset` = 104. Save's right edge sits **40 to 84pt** right of every `☰` above it |
| Cancel and Save are different widths | both take their intrinsic width; "Cancel" is six characters and "Save" is four |

Plus one bug worth fixing in the same pass: **`inline-name-field` is dead.**
Lines 221 and 233 both call `.accessibilityIdentifier` on the same `TextField`,
so `inline-rename-field` wins and any test querying `inline-name-field` finds
nothing.

## 7.2 Inline creation: the layout

**Two lines, not one.** At 393pt a single row leaves the field 189pt, about 27
characters. Two lines give it 365pt, about 52, and let both lines align to the
list's own grid.

```
┌──────────────────────────────────────────────────┐
│  ┌────────────────────────────────────────────┐  │   line 1: field, full width
│  │ Set list name                              │  │
│  └────────────────────────────────────────────┘  │
│                          [ Cancel ]  [  Save  ]  │   line 2: right-aligned
└──────────────────────────────────────────────────┘
 20                                              8
```

| | Value | Derived from |
|---|---|---|
| Row height | **92pt** = 8 + 34 + 8 + 34 + 8 | two control heights, not a literal |
| Leading | `s20` | aligns with row titles. In Edit mode, `s20 + checkboxGutter` |
| Trailing | `s8` | the same edge `RowMenuButton` sits at, so Save aligns with the `☰` column |
| Field | full width, `minHeight` 34, `Surface.paper`, 1pt `Accent.clay`, `rCtl` | one height for field and buttons |
| Buttons | `minWidth: 80`, `minHeight: 34`, `s8` apart | equal widths, so the pair reads as a pair |
| Row fill | `Accent.clayTint`, flat, no inner rounded block | the app's in-progress colour. Two fills (tint, then paper) and no third |
| Gap between lines | `s8` | |

Behaviour:

- Autofocus on appear. The row scrolls above the keyboard
  (`IPHONE_0.6.14.md` §17.7 rule 2); `.ignoresSafeArea(.keyboard)` must not
  apply to this list.
- Return saves: `.submitLabel(.done)` and `.onSubmit`.
- Save is disabled at 42% while the trimmed text is empty. Disabled, not hidden,
  so the row does not reflow as the first character lands.
- Cancel is the only discard. Tapping elsewhere does not silently throw the name
  away.
- The row sits at the **top** of the segment's list, so it is visible without
  scrolling.
- Heights scale with Dynamic Type: `max(34, scaled)`, and the 92 follows from
  them. No literal survives at accessibility sizes (§6.3 rule 1).

One component, both tabs. Only the placeholder differs: `Piece name` and
`Set list name`. Identifiers: keep `inline-rename-field`, `inline-rename-cancel`,
`inline-rename-save`, and give the container `inline-create-row` so the two
purposes are separable in tests.

## 7.3 Set list from a selection: where it lives

**The Edit-mode action bar, as a new `LibraryAction` case. Not the New panel.**

The New panel creates from nothing and its rows carry descriptions of what a
piece and a set list are. A row that appears there only when a selection exists
on another screen makes the panel's contents depend on state the reader cannot
see from it. Verbs that act on a selection already have a home, and
`LibraryActions.bar(for:)` is it.

```swift
case newSetlist          // LibraryAction
identifier: "bar-new-setlist"
bar(for: .pieces) -> [.newArrangement, .newSetlist, .delete]
needsExactlyOne: false
```

`.setlists`, `.arrangements` and `.mixed` are unchanged. Arrangements already
have `Add to set list…`, which is a different verb with a different target.

### The bar does not fit, so it yields

At 393pt the bar has **353pt**. Measured:

| Rung | Contents | Width | |
|---|---|---|---|
| 0 | `5 selected` · New arrangement · New set list · Delete 5 pieces | 469 | over by 116 |
| 1 | drop the `N selected` readout | 395 | over by 42 |
| 2 | **+ short verb labels** | **336** | **fits, 17 spare** |
| 3 | + Delete loses its count | 270 | fits, 82 spare |

Yield in that order, and stop at the first rung that fits. At 393 that is rung 2:

```
│              [ Arrangement ] [ Set list ] [ Delete 5 pieces ] │
```

- The readout goes first because it is a readout, and every selected row already
  carries a checked box.
- `Delete` keeps its count as long as possible. It is the destructive verb and
  the count is the safety.
- Short forms are `Arrangement` and `Set list`. The visible label is a noun and
  the selection supplies the verb; the **accessibility label carries the whole
  sentence**: `New set list from 5 pieces`.
- Rung 4, if a rung 3 bar still does not fit (accessibility sizes), is two rows,
  constructive above destructive, which is `IPHONE_0.6.14.md` §6.3 rule 4
  arriving one control early.

Same measured discipline as §14 of that document: a pure function that takes the
bar width and returns the rung, testable without a screen.

## 7.4 Set list from a selection: what it builds

**A set list holds arrangements, and a piece is a folder.** `LibraryActions`
says so at the top of the file and it is the reason `.addToSetlist` is not in
the pieces bar today. So this action has to choose an arrangement per piece, and
the choice must be stated rather than silent.

Rules:

1. **Arrangement #1 of each piece**, in the order the pieces appear under the
   list's current sort.
2. A piece with **no arrangements is skipped**.
3. Nothing is created if every selected piece is skipped; the notice says so and
   the selection survives.
4. After creating, the app switches to the Setlists segment, scrolls to the new
   row, and opens §7.2's inline row **pre-filled with the auto-name, focused,
   with the text selected**, so one keystroke replaces it. Edit mode ends.
5. A notice bar states what was assumed, and only when there was an assumption:
   `Added #1 of 3 pieces with several arrangements. Change them in the set list.`
   and `2 pieces had no arrangements and were skipped.`

## 7.5 The auto-name heuristic

Four rules, first match wins. Every input is the selected pieces, in sort order.

```
1. TITLES      2 ≤ count ≤ 3, and the joined names fit 34 characters:
               "Autumn Leaves, Sous le ciel"          (", " between)

2. COMPOSER    every piece has the same non-empty composer:
               "Piazzolla, 7 pieces"

3. WEEKDAY     "Thursday set"

4. DEDUPE      if the name is taken, append " 2", " 3", … until it is free
```

**34 characters** is measured, not chosen: a set list row now reserves
`rowTwoControlInset` (104) for share and `☰`, leaving 253pt of title at 13.5pt,
which is 34 characters before truncation. A generated name that truncates in the
row it is generated into is the wrong default.

**Composer equality is strict**: trimmed, case-folded, punctuation stripped,
compared whole. No surname matching. OMR yields `J.S. Bach`, `Johann Sebastian
Bach` and `BACH, J.S.` for one person, and a fuzzy matcher that gets it wrong
produces a confidently wrong name. Rule 2 not firing costs a weekday; firing
wrongly costs a lie. If the strings differ, fall through.

**Weekday, not a date.** `Thursday set` is what a gigging musician writes, and
the dedupe rule handles a second one the same day. `Set list, 11 Sep` is more
precise and less like anything anyone says.

**No tag rule.** There are no user tags: `LibraryFilter` is four derived filters
(`unfiled`, `omrDrafts`, `hasSources`, `inASetlist`), and real tags need an
engine change (§7 of `NAVIGATION_SYSTEM.md`). A rule over a field that does not
exist is not a rule.

**No `New set list N` fallback.** Rule 3 always produces a name, and rule 4
always makes it unique, so the generic fallback is unreachable. If the engineer
finds a path to it, that path is a bug.

## 7.6 Acceptance

1. `inlineCreateAlignsWithTheList`: the inline row's field leading edge equals a
   row title's, and Save's trailing edge equals the `☰` column's, on both tabs.
2. `inlineCreateIsOneHeight`: field and both buttons report the same height at
   Large, xxxLarge and AX3, and no frame is a literal.
3. `inlineNameFieldIsAddressable`: `inline-create-row` and
   `inline-rename-field` both resolve. Fails today: two identifiers sit on one
   `TextField`.
4. `theBarFitsAtEveryWidth`: for 320 to 1366 and every `DynamicTypeSize`, the
   chosen rung's width is ≤ the bar width.
5. `setlistFromSelectionPicksFirstArrangements`: three pieces selected produce a
   set list of their three `#1` arrangements, in sort order.
6. `emptyPiecesAreSkippedAndReported`: a piece with no arrangements is absent
   from the set list and named in the notice.
7. `autoNameRules`: two pieces give joined titles; seven by one composer give
   `<Composer>, 7 pieces`; a mixed seven give `<Weekday> set`; a repeat gives
   ` 2`; no output exceeds 34 characters except a composer name that is itself
   longer.
8. `theNameIsAProposal`: after creation the inline row is focused with the
   generated name selected, and one keystroke replaces it whole.
