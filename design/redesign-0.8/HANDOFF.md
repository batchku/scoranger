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

(none yet)
