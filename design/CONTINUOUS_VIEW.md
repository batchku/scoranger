# Continuous view and the three-way layout control

Designer's spec, 2026-08-29. Builds on NAV_REVISION_0.4.1 §6 (the paged canvas)
and amends its zoom rule; see "Zoom" below.

## The control

Page / spread / continuous is ONE question with three answers, so it is one
control, not three booleans. It REPLACES the two-page-spread button.

- Model: `ScoreLayout { page, spread, continuous }`. `twoPageSpread` stays as a
  derived `layout == .spread` so nothing downstream has to change at once, and
  so the impossible state (spread AND continuous) cannot be represented.
- Placement: the score top bar's actions cluster, immediately left of "…".
- Always visible in the score view. ABSENT in performance mode.
- "… -> Score display" shows the same three-way value. One property, two
  surfaces.
- iPhone shows page / continuous only: a spread is meaningless at that width
  and the bar already overflows.

## Treatment

The existing segmented control (the Pieces/Setlists one) at bar scale:

- 3 cells, 40pt wide x 34pt tall, radius `rCtl`, 1pt `line2` border, 1pt `line`
  dividers.
- Active: `clayTint` fill, `clayStrong` glyph, clay inset outline.
- Inactive: `panel` fill, `ink2` glyph.
- Glyphs: `doc` (page), `book.pages` (spread), `arrow.left.and.right`
  (continuous).
- VoiceOver: ONE `.adjustable` element, "Score layout: <value>", swipe to
  change -- not three buttons.

## Continuous mode

All staves, running left to right to the end of the score, no page wrapping.
Verovio lays it out with `breaks: "none"`. It is for arranging and composing.

### Zoom (amends NAV_REVISION_0.4.1 6.4)

The paged canvas clamps zoom at fit-PAGE. Continuous mode is the sanctioned
exception and clamps at fit-HEIGHT instead: there is no page to fit, and the
height is the only bound the surface has.

### Tap zones

A tap advances ONE VIEWPORT WIDTH rather than turning a page. Performance mode
keeps its horizontal advance.

### Thumbnail strip

Spread grouping goes. The strip becomes position markers that scroll to an x
offset, and the current-page outline becomes a viewport indicator.

## Known limits (engineering, to be confirmed by the spike)

- Ink is keyed to a PAGE (`DrawingStore` keys by page index). Continuous mode
  has one surface, so page-keyed strokes have nowhere to land; ink is expected
  to be unavailable in continuous mode in the first build rather than silently
  dropped.
- Verovio's page width has a ceiling, and a long score as a single system makes
  a very large SVG to rasterise on an iPad. If one system per score does not
  render, the fallback is a segmented panorama (continuous within chunks).
