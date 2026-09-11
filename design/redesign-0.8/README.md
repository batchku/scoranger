# Scoranger 0.8 redesign options

Two rounds of options for the 0.8 redesign, each answering
`design/REDESIGN_BRIEF_0.8.md` on the same ten screens, with a stance, a
components sheet and a build-cost note. Drawn against the 0.7.4 build 191
photographs in `design/shots-0.7.4/` (see the note at the end).

## The spec (2026-09-11)

The owner chose Notebook. `notebook-spec.html` is the full UI specification
for review: foundations, components, the navigation map, and wireframes for
every screen and every panel state (56 frames: library 12, piece 2,
arrangement 4, set list 7, score 15, settings 10, phone 6), the label
rewrite and the build-cost note. `notebook.css` is the corrected Notebook
layer over `round2.css`; the eight corrections from the owner's annotated
screenshots of option 8 are listed at the top of the spec and marked in the
CSS: panel on `panel` not white, no tab column, knobs without ticks, a flat
tint band for a selected row, a labelled Perform button, a back arrow instead
of ✕, a search field that never wraps, and nothing cut off when the panel
opens. Thumbnails moved to a narrow rail on the left of the score.

## Round 2 (2026-09-10, after the owner's notes on round 1)

Three options that share one skeleton, built from what the owner kept from
round 1 and what they rejected:

- kept: rounder, warmer forms; larger type; the next level in a right panel
  (Margin); Desk's settings split; Stand's full-width list; Desk's clear bottom
  drawer with more controls in it; the left/right splits of the set list,
  Account, and Arrangement/Versions screens;
- rejected: a drawer taller than one row; row operations that send the finger
  down to a shelf; the knob's LED anywhere but the centre of the dial; anything
  that pops up at the bottom and has to be closed.

So in all three: lists are full width; a row's own actions open inside the row
(☰ becomes ✕, the actions take the meta line's place); the next level opens in
a right panel **anchored at the row that opened it**; the drawer is one 56pt
line with transport, one knob per part (LED in the centre; tap it to mute),
tempo, position and the panel toggles; settings is index-left, section-right;
the OMR offer and the invitation live in the panel, never at the bottom.

| # | Option | What makes it different | Artifact |
|---|---|---|---|
| 6 | [Ledger](option-6-ledger.html) | Typographic and ruled: 68pt lines, a 30pt folio in the gutter, words for buttons. The panel block is tied to its row by a 2pt clay leader and a dot. Drawer on `panel` under a clay rule. | https://claude.ai/code/artifact/3719aeae-9ca6-462e-947d-caaf4aa39eeb |
| 7 | [Kiln](option-7-kiln.html) | Clay as a material: a solid clay plate heads the library, the drawer is solid clay with white-arc knobs, the panel is a white sheet with a 5pt clay mark at the row's height. Numeral as a clay disc. | https://claude.ai/code/artifact/d2ce0466-977f-4bcb-b333-583603ad37f5 |
| 8 | [Notebook](option-8-notebook.html) | A notebook page on a `band` table, dashed rules, capsule controls, a ring-stamped numeral. The panel is a **tabbed sheet**: one tab per sibling on its spine, the active tab level with the row, so Versions, Parts, Details and Set lists switch without going back. Chat becomes a tab of the score. | https://claude.ai/code/artifact/89a0cf92-f018-4500-a57a-289300d122d9 |

`round2.css` holds the shared skeleton (split, panel, in-row actions, the
one-line drawer, the LED-centred knob, the settings split).

## Round 1

Five options, each with its own disclosure pattern. Open the HTML files
directly, or the published artifacts:

| # | Option | Disclosure pattern, in one sentence | Transport and mixer | Artifact |
|---|---|---|---|---|
| 1 | [Stand](option-1-stand.html) | Anything that opens, opens in a shelf at the bottom, sized to its content and capped at 300pt, so the page above never moves. | The shelf's resting row; Pages and Mixer are tabs on its lip. Performance mode leaves a 5pt clay lip. | https://claude.ai/code/artifact/23eec31e-7239-489a-b21e-873cfe9d9b4f |
| 2 | [Margin](option-2-margin.html) | Every action opens in a fixed 360pt column at the right; the page beside it keeps its width and its place. | Two ledger lines under the page, transport then mixer. Performance mode leaves a clay bookmark at the top right. | https://claude.ai/code/artifact/4a6650bc-6ae3-43ee-b039-e0cae25bd50e |
| 3 | [Turnover](option-3-turnover.html) | What you tap turns over in its own footprint to show its options and turns back; nothing else changes size or position. | One floating 64pt capsule with two faces. Performance mode folds it to a 44pt coin. | https://claude.ai/code/artifact/47af14e7-a381-4736-94dd-9580cb723061 |
| 4 | [Desk](option-4-desk.html) | Anything deeper slides in as a new sheet beside the one you are on, which stays visible as a spine; sheets never stack, dim or push down. | A drawer with rounded shoulders across the bottom; pull it for the mixer or the pages. Performance mode leaves a dim lamp switch. | https://claude.ai/code/artifact/a5d36291-fda9-4d2c-9b4e-23c87a2d4c7f |
| 5 | [Ribbon](option-5-ribbon.html) | A destination replaces the content area in place under a ribbon that names where you are; choices live in a fixed chip strip, so nothing drops down or pushes. | A 60pt dock on `band`; the mixer is a fixed 120pt row above it. Performance mode folds both to 4pt clay lines. | https://claude.ai/code/artifact/84cbcd1e-7c4f-4afe-bc72-e46afe424c57 |

## What every option keeps

The palette (`Theme.swift`, `DESIGN_SYSTEM.md` §1) unchanged, including the one
clay accent. The three type families and the ladder, with one retirement each
option calls out: the 10pt tracked-caps `label` role has no home once the band
headers go. Score first. The `#N` numeral as the identity mark, re-dressed per
option (clip, folio, badge, stamp, square). No login gate: every Settings screen
is drawn signed out, and the share sequence shows the signed-out branch. 44pt
hit targets on every control, including the ones drawn smaller.

## What every option changes

Corner radii and edges (6 to 999pt, per option; no hard 1pt `line2` borders on
controls in any of them). Every label in the brief's §4 list, rewritten to one
or two words in each option's Labels table; the sentences become notes under
the control they explain. Every disclosure that today expands in place and
pushes the page down. The mixer's floating window (drag, park, clamp, collapse)
goes in all five; the knob strip's anatomy from `MIXER_WINDOW.md` §13 stays.

## Files

- `option-N-*.html` — one self-describing page per option: stance, the ten
  screens at iPad width (1194 × 834), the two sequences as step strips, the
  components sheet, the labels table, the cost note.
- `common.css` — the fixed app palette, the iPad frame, and a shared component
  vocabulary each option restyles through tokens.
- `common.js` — the icon sprite (stand-ins for the SF Symbols the app uses),
  a deterministic pseudo-engraving so the score reads as a score, and frame
  scaling. The engraving is a stand-in for Verovio's output, never a claim
  about the notation.

Fonts load from Google Fonts (Space Grotesk, Inter, IBM Plex Mono). Offline the
pages fall back to system faces and the proportions drift slightly.

## About the photographs

`design/shots-0.7.4/` is the full `DesignerSweep` export committed in
d02ee36f (81 frames, build 191, landscape `L-` and portrait `P-`). Two things
to know when reading it:

- Several `L-` names do not match their contents, because the result bundle's
  attachment order drifts from the sweep's shot order once a step misses its
  control. `L-24-settings.png` and `L-12-setlist-member-open.png` both show
  the score with a selection chip; `L-33-score-options.png` is right. Judge
  each file by what it shows, not its name.
- The `L-` frames are the raw portrait framebuffer and need
  `sips -r -90 <file> --out <file>` to read the right way up, as the sweep's
  own header says. They are left as committed here.

Where the sweep did not reach a screen (Settings, the set list screen), the
mockups are grounded in `SettingsView.swift`, `ManagementScreens.swift` and
`NAV_MODAL_FREE_0.4.2.md` §3.5 and §6 instead.

## Next

The owner picks one option, or a combination; then `design/DESIGN_SYSTEM.md`
is rewritten as the 0.8 spec and `Theme.swift` follows it. No app code was
touched for these mockups.
