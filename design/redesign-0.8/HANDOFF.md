# 0.8 handoff: from the design session to the implementing session

Written 2026-09-11 by the design session (scoranger-94) for whichever session
implements and releases 0.8. Ali has asked for the redesign to reach internal
TestFlight as staged builds.

## Where

Branch `design/0.8-notebook` (off `rel/0.7.1`), commit 3e658b00. No app code
changed in it. Branch from it so the spec travels with the code.

- `design/DESIGN_SYSTEM.md` — the 0.8 spec ("Notebook"). Read §0 first: the
  sixteen binding rules from Ali's annotated reviews, marked [C1]–[C16]. §12
  is the staged build plan below.
- `design/redesign-0.8/notebook-spec.html` — 56 wireframes, every screen and
  panel state, iPad and phone. Open it in a browser. `notebook.css` is the CSS
  layer; its `[Cn]` comments map to the rules.
- `design/redesign-0.8/README.md` — how the folder is organised. Rounds 1 and
  2 are context; the spec is the deliverable.

## The ask

One internal TestFlight build per stage, `ios/scripts/gate.sh` then
`ios/scripts/deploy_testflight.sh`, as for 0.7.4 build 191.

1. **0.8.0 tokens only.** `Theme.swift`: `band` as the app ground; radius 999
   on controls, 22 on pages; dashed `line2` rules instead of borders; the type
   ladder of §2 (one step larger); the `#N` numeral as a clay ring stamp; knobs
   without the pointer tick [C3]; Perform as a labelled button in the score
   bar [C5]; ‹ with the origin's name instead of ✕ [C6]; score title one line
   with an ellipsis [C16]. Shapes unchanged; everything restyles.
2. **0.8.1 the Tray.** One 56pt line replacing `ScoreFooter` and
   `MixerWindowPanel` / `MixerWindowStrips`: transport, one knob per part
   inline (the LED at the dial's centre is the mute), tempo knob, position and
   scrubber. Drag, park, clamp and collapse go; `MIXER_WINDOW.md` §13's knob
   anatomy stays.
3. **0.8.2 Panel, RowActions, ThumbnailRail.** The right panel on `panel`
   [C1], no tabs [C2]; a row's own actions inside the row on a flat tint band
   [C4]; folds Options, the ☰ management bands, the version dropdown and
   switcher band, Sort and Filter bands, the OMR offer and `PanelDialogs`
   (inline confirm) into it. The tool row wraps when the panel opens; nothing
   is clipped [C7, C8].
4. **0.8.3 SettingsSplit, filters, book.** Filter groups from the data model
   [C9]; Date added on rows and in Sort [C10]; long-press selection [C11]; the
   book filmstrip [C12]; Tags on Details [C14]; the resizable chat compose
   [C15].
5. **0.8.4 phone layout.**

## Two data-model notes for stage 4

- Instrument filters read the parts snapshot of each arrangement's latest
  version. A never-converted scan matches no instrument; the count on each
  capsule makes that visible.
- Date added is the first version's timestamp.

## When a wireframe and the doc disagree

`DESIGN_SYSTEM.md` wins. Tell Ali, or leave a note in this file under
"Questions" and the design session will fix the spec.

## Questions

From the implementing session, 2026-09-11 (build 192, the whole Notebook in
one build at Ali's word):

1. **Import and New in the tool row.** §7.6 lists Import, New and New set
   list as primary actions. Import has four ways in (file, photos, folder,
   book) and the row's fit model has two verbs, so Import and New each open
   a panel state listing their choices, with the sentence under each as a
   note. Say if a third button is wanted instead.
2. **A set list row's Rename and a book's Rename.** A set list renames in
   place (L8). The engine has no rename for books, so a book row offers Open
   and Delete only (L9 lists Rename).
3. **The knob's LED** lights while the part sounds (§1 `ok`) and is the mute
   when tapped (§7.8): both hold, so at rest on bar 1 only the parts with a
   note on the downbeat are lit. If the LED should read "on" for every
   unmuted part regardless, the spec should say which.
4. **The OMR offer** is still More's Make editable row and the progress chip,
   not a panel state (SC13) -- deferred to 0.8.1 with the phone's foot strip
   and the score bar's second row (Ph2, Ph4).
5. **Set list rows**: the row and its Open action open the set list's screen;
   the Play capsule beside ☰ plays from the top (L7). 0.7 opened playback on
   the row tap; tell Ali if that muscle memory matters more than L7.

From the follow-up session, 2026-09-11 (build 194, Ali's list from 193):

6. **The inline naming row** (Ali's item 4) is built to REDESIGN_BRIEF_0.8
   §7.2: two lines, field at the title edge, Cancel and Save at the row's
   control edge, one control height (34, scaled), Save disabled while the
   name is empty, Return saves. Photographs:
   `design/shots-0.8.0/setlists-new-inline-row.png` and
   `setlists-new-inline-row-named.png`. `InlineCreate` asserts the grid,
   the heights at Large/XXXL/AX3 and the identifiers.
7. **Set list from a selection** (item 5) is built to §7.3–7.5: the
   Edit-mode bar for pieces ("New set list", yielding to "Set list" and
   then Delete's count by measurement, `LibraryActionBarLayout`), #1 of
   each checked piece with a notice for what was assumed, the four naming
   rules (`SetlistNaming`), and the proposed name arriving selected in the
   new row's rename field. Photographs: `pieces-edit-checked.png` and
   `setlist-from-selection.png`. Open: rung 4 (two rows) is used at
   accessibility sizes; the brief's 393pt case lands on rung 2 as measured
   (rungs at Large, 5 pieces: 484 / 401 / 341 / 285).
