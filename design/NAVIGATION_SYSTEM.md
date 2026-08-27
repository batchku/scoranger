# Scoranger navigation & IA redesign

Design-first. No app code has been changed. Mockups: `scoranger-navigation.html`
and `png/nav-*.png`. This extends `DESIGN_SYSTEM.md` — the palette, type and
instrument-panel treatments are unchanged; only the information architecture and
the chrome that expresses it are new.

**The move:** browsing and reading become separate places. Today one screen
carries a library overlay, a canvas and a chat overlay at once, with a pill
holding everything. In the new IA a **bottom tab bar** holds *Home* and *My
Library*; a score opens **over** them as its own place and closes back to where
it came from.

---

## 1. Reference patterns, and what we take

Researched from the reference app's own documentation, not guessed. What we copy
is placement and flow; nothing about its look comes across.

| Reference pattern | Our version | Deviation and why |
|---|---|---|
| Bottom tabs: Home · My Library · Shared Library | Home · My Library · *(third slot reserved)* | We have no sharing and no accounts. The third tab is drawn disabled and labelled, so the bar is not re-laid-out when sharing lands. |
| Home: recents, search, coloured tool panels (tuner, metronome, store) | Home: search, **four real actions**, recent pieces, recent setlists | Their tools are audio utilities we do not have. Inventing a tuner as chrome would be a lie; our four panels are all things the app already does. Panels are differentiated by **fill weight** (clay tint / band / well / panel), not by four colours — the three-colour budget holds. |
| Top-left help / inbox / settings; top-right account avatar | help · inbox (with count) · settings; top-right **engine chip + LED** | No accounts. We do have two engines, and which one is running is the thing you actually need to know at a glance. The inbox is real (`AppState.scanInbox`). |
| My Library: segmented Pieces/Setlists, title + count, search, sort, tags, Edit, A–Z rail, rows with thumbnail, + button | Same, one for one | Only the tag filter differs — see §7. |
| Row subtitle = composer / source | Piece rows: composer · N arrangements. Setlist rows: the running order by `#N` | Our setlists hold **arrangements**, not pieces, so the subtitle names them the way chat does. |
| Score: X close · centred title with dropdown (switches **parts**) · Edit · AI · Bookmark · … | X close · centred title with dropdown (switches **arrangement #N, then version**) · Edit · **Ask** · **Spread** · … | We have no parts-as-documents and no bookmarks; we do have two things worth switching, and they nest. The AI slot becomes chat, which is genuinely our AI action. The bookmark slot takes the two-page spread toggle — a real feature currently buried in Settings. Bookmarks are deferred (§7). |
| "…" → categorised preferences, each opening a sub-screen, Settings among them | Same two-layer menu, our nine entries | Their Note Identifier, Piano and LiveScores have no counterpart here and are dropped rather than faked. |
| Page/measure counters near the score | `pp. 3–4 / 12` and `bar 21`, mono, top-right | Bar number needs the geometry layer (§7). |
| Two-page spread | We have it (`AppState.twoPageSpread`) | Promoted from Settings to the top bar. |
| Page thumbnail strip in the bottom bar | Same, **grouped in spreads** | Grouping matches what a turn actually does when the spread is on. |
| Transport pinned at the bottom: prev/next, scrubber, play, loop, record | Drawn, mostly inert; prev/next are **live** and step the setlist | We have no playback engine. See §7 and the recommendation in §9. |
| Prev/next arrows cycle Library/Setlist items | Prev/next step the **current setlist**, labelled `setlist · 2 of 4` | This is the one piece of the transport that works today and it is the most useful thing on a music stand. |
| Page turns: tap the left/right margins; swipe; Pencil works too | Same, but only in the modes where it cannot cost you a selection — §6 | The important conflict in this whole redesign. |

Sources: [Exploring the Score View](https://support.newzik.com/en/support/solutions/folders/77000104128) ·
[The Home Screen](https://support.newzik.com/en/support/solutions/articles/77000151789-the-home-screen) ·
[My Library vs Shared Library](https://support.newzik.com/en/support/solutions/articles/77000151819-my-library-vs-shared-library)

---

## 2. The object model, unchanged

The IA has to carry what the engine already models. Nothing here is new data:

```
piece ──< arrangement (#N, numbered within its piece) ──< version (vNNN)
                     └──< source (sNN, read-only edition)
setlist ──< arrangement   (ordered; arrangements, not pieces)
```

Consequences for navigation:

- **A piece is not openable.** Opening a piece means opening one of its
  arrangements. One arrangement → open it. Several → the arrangement sheet (N4).
- **`#N` is only meaningful inside a piece.** Unfiled arrangements have no
  number, so library rows for them show no numeral and no reserved space.
- **The title dropdown is two-level** because our hierarchy is: arrangements of
  this piece, then versions of this arrangement.
- **A setlist is a running order of arrangements**, which is exactly what the
  transport's prev/next steps through.

---

## 3. Places and transitions

| From | Action | To |
|---|---|---|
| Home | tap a recent piece (1 arrangement) | Score view |
| Home | tap a recent piece (2+) | Library → arrangement sheet |
| Home | tap a recent setlist | Library → Setlists, that setlist expanded |
| Home | Ask Scoranger | Score view of the last-opened arrangement, chat open |
| Library · Pieces | tap a row | Score view, or arrangement sheet |
| Library · Setlists | tap a row | that setlist's arrangements, in order |
| Score view | X | back to wherever it opened from |
| Score view | title dropdown | switch arrangement or version **in place** |
| Score view | transport prev/next | previous/next arrangement in the setlist |
| anywhere | tab bar | Home / My Library |

The score view is presented **over** the tab bar (full screen), not as a third
tab: it is a document you are in, and X is how you leave. Its state (page, zoom,
selection, chat) survives a close-and-reopen within a session.

---

## 4. Screen specs

Sizes are iPad landscape; the phone follows in §5. Every value below is either
already in `DESIGN_SYSTEM.md` §3–4 or listed as a new token in §5 here.

### 4.1 Home — `nav-01-home.png`
Top row: help · inbox (clay badge with the count waiting) · settings, then the
engine chip (LED + `on-device`/`remote`) at the trailing edge. Search field
(paper fill, 1pt `line2`). Four quick-action panels, equal width, 104pt tall,
each a glyph + `titleS` + an 11pt description; fills are `clayTint`, `band`,
`well`, `panel` in that order — the first is the one we want tapped.
Then `RECENT PIECES` and `RECENT SETLISTS` band labels, each with an "All …"
link, and 56pt rows: thumbnail, title, subtitle, derived chips, and the last
touch in mono on the trailing edge.

### 4.2 My Library — Pieces — `nav-02-library-pieces.png`
Segmented control centred at the top (`Pieces` | `Setlists`, active =
`clayTint` + 1pt `clay` inset). `My library` title at 26pt Space Grotesk with a
mono count. Search. Then the control bar: `Sort: name`, `Filter`, and `Edit`
trailing. Alphabet headers are band strips; rows are 56pt with a 44×57
thumbnail. The A–Z rail sits 5pt off the right edge, mono 9.5pt, letters that
have content in `clayStrong`, the rest `ink3`. FAB bottom-right, 54pt,
`clayPress`, radius 3 — square-shouldered, per the instrument-panel rule that
only the pill and ink bar are round.

**Sorts:** name, composer, recently changed, arrangement count. The rail is
shown only under *name* — under any other sort it would lie, so it hides.

**Filters (derived, not a tag store):** unfiled · OMR drafts · has sources ·
in a setlist. See §7 for real tags.

### 4.3 My Library — Setlists — `nav-03-library-setlists.png`
Same skeleton. Subtitle is the running order (`Cavatina #2 · Libertango #1 …`),
chips are the count and `ORDERED`. Edit enters reorder/delete.

### 4.4 Piece → which arrangement — `nav-04-arrangement-picker.png`
A `PanelSheet` over the library: band header, one row per arrangement with the
numeral badge at 21pt, thumbnail, parts and version count, last touch; then a
`Sources` band, read-only; then `New arrangement of this piece` (primary) and
`Rename piece`. This screen is where today's expandable sidebar rows go.

### 4.5 Score view — `nav-05` … `nav-11`
- **Top bar** 52pt, `panel`, 1pt bottom border. `X` at 34pt leading; the title
  block centred (numeral 19pt clay + name 15pt Space Grotesk + `piece · vNNN` in
  mono 10.5 + chevron); trailing actions: pencil (Edit), speech bubble (Ask),
  spread, `…`. Active actions take `clayTint` + 1pt `clay`.
- **Canvas** fills the space between the top bar and the strip; pages keep the
  existing renderer, spread and zoom behaviour.
- **Counters** float top-right, mono in bordered chips: `pp. 3–4 / 12`, `bar 21`.
- **Thumbnail strip** 96pt, `panel`, above the transport: 52×68 page thumbs,
  grouped in dashed spread brackets when the spread is on, current spread
  outlined 2pt `clay`, page numbers in mono. Tap = jump.
- **Transport** 56pt, `band` fill: `prev`/`next` (live, stepping the setlist),
  a `setlist · 2 of 4` chip, then play/loop/record, elapsed/total and the
  scrubber at 42% opacity with a dashed `playback not wired yet` tag.
- **Title dropdown** (N6): a 360pt menu under the title — band `Arrangements of
  Cavatina`, the `#N` rows, band `Versions of #2`, the recent versions, and
  `All 14 versions ›`.
- **"…" menu** (N7/N8): 320pt. Layer one is Performance mode (a switch, in the
  highlighted top row), then Score display, Annotations, Selection & chat,
  Transpose, Versions, Piece & arrangement details, Share & export, Settings.
  Layer two replaces the menu contents behind a back row; nothing is a modal.
- **Edit mode** (N9): the ink bar rises above the strip, in pill language, and
  states the Pencil's meaning (`Pencil: ink`). No lasso tool — see §6.
- **Ask** (N11): the chat panel from the current design system, docked right at
  380pt, top-aligned under the top bar. Strip and transport shorten instead of
  hiding, so the score keeps its position.
- **Performance mode** (N10): top bar collapses to 38pt (X + `PERFORMANCE`),
  strip and transport hide, the score gets the whole screen, and the page-turn
  zones become live for every input.

---

## 5. New tokens and components

Extends `DESIGN_SYSTEM.md` §7. Everything below reuses existing colour, type and
border tokens; only geometry is new.

| # | Component | Key metrics |
|---|---|---|
| 12.1 | Tab bar | 64pt, `panel`, 1pt top border; item = 19pt glyph in a 3×16 `clayTint` pill when active + 10pt caps label; disabled tab at 38% |
| 12.2 | Quick-action panel | min 104pt, radius 3, 1pt `line2`, fills `clayTint`/`band`/`well`/`panel`; glyph 20pt `clayStrong`, title `titleS`, description 11pt `ink2` pinned to the bottom |
| 12.3 | Search field | paper fill, 1pt `line2`, radius 2, 10×12 padding, 13pt, `ink3` placeholder |
| 12.4 | List row (`lrow`) | 56pt min, 20pt side padding, 12pt gap; thumbnail 44×57; title `titleS`; subtitle 11pt `ink3`; chips row; trailing meta in mono |
| 12.5 | Derived chip | 1pt `line2` on `band`, radius 2, 9.5pt caps +0.08em. Variants: count (`clayTint`/`clayBorder`/`clayStrong`, mono), warning (`#FBF2E6`/`#E8CFA6`/`#8A5A12`) |
| 12.6 | Alphabet header | band strip, 13pt Space Grotesk 700 `clayStrong` |
| 12.7 | A–Z rail | 16pt wide, mono 9.5pt, right edge, top 170 / bottom 80; present letters `clayStrong`; 44pt hit slop, haptic per letter |
| 12.8 | FAB | 54pt square, radius 3, `clayPress`, white 26pt glyph, `ePill` |
| 12.9 | Score top bar | 52pt (38pt in performance); buttons 34pt, radius 2 |
| 12.10 | Title block | centred, 5×10 padding; opens to a 360pt two-section menu; `open` state takes `well` + 1pt `line2` |
| 12.11 | Position counters | mono 10.5pt in `panel` chips, 1pt `line2`, radius 2, top 60 right 14 |
| 12.12 | Page thumbnail strip | 96pt; thumb 52×68, 1pt `line2`; current 2pt `clay` outline; spread group in a 1pt dashed bracket |
| 12.13 | Transport | 56pt on `band`; buttons 32pt; track 4pt `well` with 1pt border; inert parts at 42% with a dashed tag |
| 12.14 | Two-layer menu | 320pt panel, radius 3, `eSheet`; rows 10×12 with 18pt leading glyph, trailing value in mono `ink3` and a chevron; back row on `band` |
| 12.15 | Page-turn zones | outer 22% of the canvas each side; a 16% clay gradient shown only while learning or in performance mode |

---

## 6. Gesture arbitration — the part that can break what we built

Today (already shipped): fingers pan and pinch through `UIScrollView`; the
**Pencil never pans**; the Pencil lassos to select music, or inks when markup is
on; two fingers tap to undo ink; a Pencil tap adds or drops one element from the
selection. That model is the app's most delicate piece of engineering and the
page-turn patterns collide with it head-on.

**The rule: the Pencil means exactly one thing per mode, and the mode is stated
in the top bar.**

| Input | Read | Edit (ink) | Performance |
|---|---|---|---|
| finger drag | pan / scroll | pan / scroll | pan / scroll |
| two fingers | pinch zoom | pinch zoom | pinch zoom |
| finger tap, outer third | **turn page** | **turn page** | **turn page** |
| finger tap, centre | dismiss transient chrome | — | re-show the collapsed bar |
| two-finger tap | undo ink | undo ink | — |
| Pencil drag | lasso → selects music | draws ink | **turn page** |
| Pencil tap | add / drop one element | — | **turn page** |
| Pencil swipe from screen edge | — | — | **turn page** |

Resolutions, stated plainly:

1. **Pencil page-turn only exists in performance mode.** In read mode a Pencil
   swipe is a lasso and must stay one; in edit mode it is ink. Performance mode
   turns selection and ink off, which is precisely what frees the Pencil. This
   is also the reference's own answer — its performance mode locks the screen to
   page turning.
2. **Finger tap-to-turn is new and safe**, because a single-finger tap on the
   page currently does nothing: fingers only scroll. It needs a threshold
   (≤10pt movement, ≤300ms) so a slow pan never registers as a turn.
3. **Zoomed in, tap-to-turn still turns.** It scrolls to the next page's top-left
   at the current zoom rather than resetting zoom.
4. **A "page turn" is a scroll, not a flip.** The renderer stacks pages
   vertically; the turn animates a scroll to the next page (or spread) boundary.
   Nothing about the layout engine changes.
5. **The lasso keeps its meaning.** The ink bar deliberately has no lasso tool,
   even though the reference has one, because in this app the lasso selects music
   for chat. Two lassos meaning two things would be the worst outcome of this
   redesign.
6. **Accessible alternatives are mandatory**: every zone tap has a button
   equivalent — the thumbnail strip, the transport's page controls, and
   VoiceOver actions on the canvas. Zone taps are invisible to Switch Control,
   so they can never be the only way to turn a page.

---

## 7. What we do not have yet

| Needed by | Gap | Where it has to be built | Cost |
|---|---|---|---|
| ~~Recent pieces~~ | **BUILT (0.4.0)** — derived from the arrangements' latest version time | — | done |
| ~~Recent setlists~~ | **BUILT (0.4.0)** — `RecentSetlists`, last-opened in `UserDefaults` | — | done |
| Tag chips / filter | No tag field anywhere | `manifest` + engine: tags on a score, `scor tag` op | medium, **engine change** |
| Bookmarks | No concept | New per-score marks with bar anchors | medium, engine + UI |
| ~~Thumbnails~~ | **BUILT (0.4.0)** — page-1 raster cache keyed `slug/version` | — | done |
| ~~Page strip~~ | **BUILT (0.4.0)**; in 0.4.2 it sets the page index directly | — | done |
| `bar 21` counter | Still absent. **Cheaper since 0.4.2**: the paged canvas keeps the viewport inside ONE page's coordinate space, so the mapping no longer spans pages | `ScoreGeometry` + the per-page element index | small–medium |
| ~~Search~~ | **BUILT (0.4.0)** — client-side over the manifest | — | done |
| Share & export | Engine has export; the score's `Share & export` row is a DEAD END (pushes to a section with no `case`) | share sheet + `EngineClient.export*` | small–medium |
| Playback transport | No audio engine at all | MIDI synth + score→time mapping | **large; out of scope** |

---

## 8. What happens to today's UI

| Today | Tomorrow |
|---|---|
| Library overlay in the canvas | Gone. Its job splits: browsing → Library tab; switching within a piece → title dropdown; stepping a setlist → transport prev/next |
| Canvas pill | Gone in the score view. Its pieces: library → X + tabs; `#N` → title block; version chip → title dropdown; gear → `…`; pencil → Edit; chat → Ask |
| Gear menu (transpose, flats, clear markup) | `…` → Transpose ›, Annotations › |
| Settings sheet | `…` → Settings › (and Home's settings icon) |
| Arrangement info sheet | `…` → Piece & arrangement details, and the arrangement sheet in the library |
| Chat overlay | Unchanged, opened from Ask |
| Two-page spread (in Settings) | Top-bar toggle |
| Selection chip and lasso | Unchanged |
| Drag-to-file rows, context menus | Move to Library Edit mode and row context menus |

The pill's *language* survives: the ink bar stays a pill, and the tab bar's
active item, the segmented control and the menu rows all reuse the
`clayTint` + 1pt `clay` pattern.

---

## 9. Risks, ranked

1. **Pencil page-turn vs lasso.** Mitigated by mode, not by heuristics. If Ali
   wants Pencil turns in read mode too, the honest options are an edge-only
   gutter (outside the page bounds) or nothing — not a timing guess.
2. **Dead playback chrome.** A transport that does nothing teaches people the
   app is broken. **Recommendation:** ship it hidden behind `… → Score display →
   Show transport (preview)`, default off, with prev/next always available;
   Ali's call, and the mockup shows it visible so he can judge.
3. **The score-view rewrite is the second structural rewrite in a month.** The
   first one (canvas root, overlays, pill) is barely landed. Every UI test that
   drives the pill breaks; the `-uiTestPencil` harness and the accessibility ids
   need re-pointing.
4. **Tab bar on iPad is unconventional.** iPadOS 18 prefers a top tab bar or
   sidebar. We are following the reference deliberately, for one-thumb reach on
   a stand; flagged so it is a decision, not an accident.
5. **`bar 21` depends on the parallel vector-score session.** If that geometry is
   not ready, the counter ships as `pp. 3–4 / 12` alone.
6. **Two hierarchies in one dropdown.** Arrangements and versions in one menu is
   dense; if it tests badly, versions move to `… → Versions ›` and the dropdown
   keeps arrangements only.
7. **Thumbnail cost.** Rastering 12+ pages twice (strip + cache) on an iPad
   Pro is fine; on an older iPad with a 60-page score it is not. Cap the strip
   to lazily rendered windows.

---

## 10. Build order (TDD-friendly)

1. **Shell**: tab bar + Home + Library screens over the existing state, score
   view still the old canvas. Tests: navigation model, sorts, filters, A–Z.
2. **Score top bar + title dropdown**, replacing the pill's identity duties.
   Tests: arrangement/version switching parity with today's version menu.
3. **Thumbnail strip + page-jump**, with the raster cache. Tests: jump maps to
   the right scroll offset at each zoom and spread setting.
4. **Page-turn zones + performance mode**, behind the mode rule in §6. Tests:
   the arbitration table, one case per cell — this is where regressions will be.
5. **"…" two-layer menu**, moving Settings, Transpose, Annotations, Details in.
6. **Transport**, prev/next live, the rest inert per §9.2.
7. **Gaps** from §7, each on its own branch: search, thumbnail cache, share &
   export, recents, then tags/bookmarks if wanted.

---

## 11. Decisions I made that Ali may want to overturn

1. Four quick actions, all real, instead of six tool panels.
2. Engine chip instead of an account avatar.
3. Spread toggle in the bookmark slot; bookmarks deferred.
4. Setlist stepping in the transport rather than a separate control.
5. Versions inside the title dropdown rather than only in `…`.
6. Transport visible but inert (see §9.2 for the alternative).
7. The third tab drawn as a disabled placeholder rather than omitted.
