# A selectable vector score

Goal (Ali's framing): the score should be a real vector representation, the way
Finale, Sibelius, Encore and Dorico engrave music — "almost like a font", where
every note, bar, clef and sign is an individually selectable object. Today it is
a flattened page bitmap, which is why nothing on the page can be pointed at.

Decision taken: draw the vectors **directly**, not rasterise-and-hit-test.

This document records what the spike measured, the architecture that follows
from it, and the one finding that changes the plan.

---

## Spike results (measured, 8-page sample quartet)

| | |
|---|---|
| Verovio `renderToSVG` | **7 ms/page** (55 ms for 8 pages) |
| XML parse of that SVG | **2 ms/page** (Python ElementTree; Swift comparable) |
| `getMEI()` | **2 ms**, 411 KB |
| SVG per page | 200–276 KB |
| Drawable primitives per page | ~600 `<path>` + ~150–250 `<use>` ≈ **800** |
| Glyph definitions in `<defs>` | **12 paths, shared** — every notehead/clef/accidental is a `<use>` of one of them |
| SVG nodes, all 8 pages | 15,279 |
| Addressable musical groups, all 8 pages | **2,764** |

Nothing here is expensive. A full parse-and-index of an 8-page score is on the
order of 80 ms, and 800 primitives per page is trivial for Core Graphics. The
performance risk is not parsing or drawing a page; it is redraw cost *during* a
pinch, which needs a prototype to settle (see Risks).

## The finding that changes the plan: Verovio ids are not durable

`BACKLOG.md` said the SVG carries "stable ids". Measured, that is wrong:

- Two `renderToSVG` calls on the **same loaded toolkit** → identical ids.
- A **fresh load of the same file** → completely different ids
  (`m5b2j45…` becomes `ul7tvng…`).
- The source MusicXML has **no `xml:id` at all** for Verovio to adopt, so it
  generates them per load.

So a Verovio id is a *session handle*, not an identity. Anything persisted —
a saved selection, a per-element annotation, an edit target — must be keyed on
something else, or it breaks on the next launch.

### What to key on instead

Verovio hands us the semantics directly, which makes a durable address easy:

```
getElementAttr("<measure id>")  ->  {'n': '1'}
getElementAttr("<note id>")     ->  {'dur': '2', 'oct': '3', 'pname': 'a'}
getMEI()                        ->  full MEI whose xml:id values MATCH the SVG ids,
                                    with <measure n="…"> and <staff n="…">
```

Also available: `getPageWithElement`, `getTimeForElement`, `getElementsAtTime`,
`getMIDIValuesForElement`, `getDescriptiveFeatures`.

Note the structural `<g>` elements carry **no** `n` or `data-*` attributes in the
SVG itself, so the numbering has to come from the MEI/attribute side, not from
scraping the SVG.

**Durable address** = (staff n, measure n, layer n, element kind, ordinal within
that layer), derived once per load by joining SVG geometry to MEI semantics on
the shared id. That address survives re-render, survives relaunch, and maps
onto music21 objects — which is most of what the item-5 research spike needed.

## Architecture

```
MusicXML ──Verovio──> SVG (geometry, session ids)
                 └──> MEI (semantics, same ids)
                          │
                    join on id
                          ▼
        display list  +  durable address  +  spatial index
                          │
              ┌───────────┴───────────┐
        vector drawing            hit-testing
      (Core Graphics)         (lasso, tap, chat context)
```

One parse serves both drawing and hit-testing. That is the whole point of the
direct-vector decision: two parsers (one to draw, one to hit-test) is the
rasterise-and-hit-test shape Ali rejected.

### Rendering options considered

| Option | Verdict |
|---|---|
| **Custom SVG → display list → Core Graphics** | **Chosen.** One parse feeds drawing and hit-testing. Verovio's output is a narrow, regular subset (paths, `use` of 12 shared glyph defs, transforms, text), so the parser is tractable. Crisp at any zoom by redrawing at the current scale. |
| `CAShapeLayer` per element | Gives identity and GPU compositing, but ~800 layers/page × visible pages is heavy, and draw-order/clipping control is worse than drawing into a context. |
| `WKWebView` showing the SVG | Truly vector and ids addressable from JS with no renderer work, but it fights the native scroll/zoom architecture stabilised in 116, complicates the PencilKit overlay, and costs more memory. Fastest way to prototype, wrong shape to ship. |
| Keep SwiftDraw, draw into a context at scale | Would give crisp vectors almost free, but SwiftDraw exposes no element identity, so hit-testing needs a second parse. Useful as a de-risking interim if the custom renderer slips; not the destination. |

## Risks

1. **Redraw during pinch** — the real unknown. Mitigations available: draw at the
   settled scale (the pattern already in place from build 116), rasterise the
   layer during the gesture and redraw on settle, or tile. Needs a prototype
   before the drawing path is swapped in.
2. **Re-indexing on every edit.** Each engine op writes a new version, which
   means a fresh Verovio load and a fresh set of ids. The index is cheap to
   rebuild (~80 ms), but a live selection must be re-resolved through its
   durable address after an edit, not carried over by id.
3. **Text handling.** `flattenTextElements` in `VerovioRenderer.swift` exists
   because SwiftDraw cannot handle nested `tspan`s (it is what build 115 fixed
   for staff labels). A native renderer handles `<text>`/`<tspan>` directly and
   that workaround eventually goes — but not while SwiftDraw is still the
   display path.
4. **The bitmap path stays until vectors render correctly.** Non-negotiable and
   already agreed. Phase A below does not touch the drawing path at all.

## Phases

**Phase A — the model (no view surface, safe to build now)**
SVG parse into a display list; MEI join; durable address derivation; per-page
spatial index; hit-test API (point, rect, lasso polygon). Headlessly testable,
and it changes nothing the user sees.

**Phase B — the drawing path**
Swap the score canvas from PDF page bitmaps to drawing the display list, behind
a flag until it renders correctly side by side with the bitmap path. This is
where the pinch-redraw question gets settled.

**Phase C — selection UI**
Selection mode, one-finger lasso, notes / bars / other picker, selection overlay,
and selection as real chat context (parts and bar numbers, not the current linear
estimate). `HighlightCaptureOverlay` is deleted only here.

**Later — item 5 research spike**
Move/duplicate of non-note elements. The durable address above supplies the
identity half; what remains is writing deterministic engine ops for relocating
expressions and spanners.
