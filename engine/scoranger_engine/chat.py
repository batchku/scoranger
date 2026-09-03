"""Provider-neutral chat agent: a Pydantic AI loop over the deterministic ops.

The model is a config choice, never a code choice. Friendly aliases in MODELS
map to pydantic-ai model strings; pick one per request ("model": "kimi") or set
a default with SCORANGER_MODEL. OpenRouter aliases need OPENROUTER_API_KEY;
google-cloud needs GCP ADC; anthropic needs ANTHROPIC_API_KEY.

The LLM never writes notation: every tool is a deterministic music21 operation
that creates a new immutable version. Tool errors are returned to the model as
data so it can correct itself (e.g. bad part names list the real ones).
"""

import json
import os

from pydantic_ai import Agent, RunContext

from . import ops, workspace

# Friendly alias -> pydantic-ai model string. Update slugs freely; nothing
# else in the system knows or cares which model is running.
# (IDs verified 2026-08-15; all tool-calling capable through OpenRouter.)
MODELS = {
    "gemini-flash": "openrouter:google/gemini-3.7-flash",        # $0.38/$1.88 per 1M
    "kimi": "openrouter:moonshotai/kimi-k3",                     # $3.00/$15 (the :exacto route was retired)
    "qwen": "openrouter:qwen/qwen3.8-max",                       # $2.00/$6.00
    "claude": "openrouter:anthropic/claude-sonnet-5",            # $2.00/$10 — best judgment in our bake-off
    "claude-opus": "openrouter:anthropic/claude-opus-5",         # $5.00/$25
    "deepseek": "openrouter:deepseek/deepseek-v4-flash",         # $0.06/$0.13 — untested, absurdly cheap
    # Direct-provider routes (no OpenRouter fee) for models that graduate:
    "gemini-direct": "google-cloud:gemini-3.6-flash",
    "claude-direct": "anthropic:claude-sonnet-5",
    # Offline smoke-testing without any API key:
    "test": "test",
}

DEFAULT_MODEL = os.environ.get("SCORANGER_MODEL", "gemini-flash")

INSTRUCTIONS = """\
You are Scoranger's arrangement agent. You manipulate a musical score ONLY
through the provided tools — deterministic operations that each create a new
immutable version. Never describe notation edits you cannot perform with a tool.

Working rules:
1. Orient first: call get_score_info before planning changes.
2. State your plan briefly, then execute it with tool calls.
3. Verify after: read each tool result; after change_instrument, relay the
   octave-shift and out-of-range report to the user.
4. If a tool returns an error, read it — bad part names include the real part
   list. Correct and retry.
5. Musical judgment is yours: sensible clefs, octaves, keys. Flag questionable
   requests instead of silently producing garbage.
6. A PIECE is the composition; an ARRANGEMENT is one scoring of it; a VERSION is
   one immutable step in an arrangement's history. You always operate on ONE
   arrangement. When the user writes '#N' they mean arrangement number N of the
   same piece, listed with its 'arr:<slug>' ref in the context: "take the violin
   part from #3" means pull_part from that ref. '#N' never means a version or a
   measure. If no numbered list is in context, say the arrangement isn't filed
   under a piece yet rather than guessing.
7. Accidentals ARE yours to control, and the tools are clean_accidentals (a
   whole part or score) and set_accidental (named notes: add, remove, show,
   hide, colour). If a reader says a part has accidentals that are already in
   the key signature, or is cluttered or hard to read, run clean_accidentals on
   that part -- do not answer that display accidentals cannot be overridden.
   Every op that changes pitches already normalises them against each part's
   own WRITTEN key, so a transposing part is judged by what is on its staff.
Answer concisely; the user sees the score update live.
"""


def _latest(slug: str):
    from music21 import converter
    return converter.parse(str(workspace.resolve_path(slug)), forceSource=True)


def _mutate(slug: str, op: str, args: dict, details) -> dict:
    # caller already applied `fn` to the score object it passes via details/score
    raise NotImplementedError


def _apply(slug: str, op: str, args: dict, fn) -> dict:
    """Load latest, apply fn(score) -> details, save as a new version."""
    try:
        score = _latest(slug)
        details = fn(score)
        entry = workspace.add_version(slug, score, op, args)
        return {"ok": True, "new_version": entry["id"], "details": details}
    except Exception as e:
        return {"ok": False, "error": f"{type(e).__name__}: {e}"}


# --- tools -------------------------------------------------------------------
# Each takes RunContext[str] where deps is the score slug.

def get_score_info(ctx: RunContext[str]) -> dict:
    """Parts, instruments, clefs, ranges, measure counts, key and time signatures of the current score."""
    try:
        return ops.info(_latest(ctx.deps))
    except Exception as e:
        return {"ok": False, "error": f"{type(e).__name__}: {e}"}


def list_versions(ctx: RunContext[str]) -> dict:
    """The score's version history (op + args per version) and its sources (other editions of the piece)."""
    meta = workspace.load_meta(ctx.deps)
    return {"versions": [{k: v[k] for k in ("id", "op", "args")} for v in meta["versions"]],
            "sources": workspace._repo().list_sources(ctx.deps)}


def keep_parts(ctx: RunContext[str], parts: list[str]) -> dict:
    """Keep only the named parts; remove all others. Part names match case-insensitively; '#N' targets by index."""
    return _apply(ctx.deps, "keep-parts", {"parts": parts},
                  lambda s: {"kept": ops.list_part_labels(s), "removed": ops.keep_parts(s, parts)})


def remove_parts(ctx: RunContext[str], parts: list[str]) -> dict:
    """Remove the named parts from the score."""
    return _apply(ctx.deps, "remove-parts", {"parts": parts},
                  lambda s: {"removed": ops.remove_parts(s, parts)})


def transpose(ctx: RunContext[str], interval: str, parts: list[str] | None = None,
              from_measure: int | None = None, to_measure: int | None = None) -> dict:
    """Transpose the whole score (or given parts) by a named interval ('M2', 'm-3', 'P8') or
    semitone count ('-3'). Set from_measure/to_measure (inclusive) to transpose only that
    measure range — required when the user targets a highlighted passage."""
    return _apply(ctx.deps, "transpose",
                  {"interval": interval, "parts": parts,
                   "from_measure": from_measure, "to_measure": to_measure},
                  lambda s: ops.transpose(s, interval, parts, from_measure, to_measure))


def transpose_elements(ctx: RunContext[str], interval: str, elements: list[str]) -> dict:
    """Transpose ONLY the given elements, by their addresses.

    Use this -- never plain `transpose` with from_measure/to_measure -- whenever the user
    refers to a selection and the context lists selected element addresses. An address looks
    like 's1/m15/l1/note#3' (staff/measure/layer/kind#ordinal); pass exactly the ones the
    context gives you, unchanged. `transpose` with a measure range moves EVERY note in those
    bars, which is wrong when the user selected particular notes."""
    return _apply(ctx.deps, "transpose-elements",
                  {"interval": interval, "elements": elements},
                  lambda s: ops.transpose_elements(s, interval, elements))


def respell(ctx: RunContext[str], prefer: str = "flats", parts: list[str] | None = None,
            from_measure: int | None = None, to_measure: int | None = None) -> dict:
    """Respell accidentals enharmonically: prefer='flats' turns G# into Ab (right for flat keys
    like F minor); prefer='sharps' does the reverse. Key signatures are untouched. Set
    from_measure/to_measure (inclusive) to respell only that measure range."""
    return _apply(ctx.deps, "respell",
                  {"prefer": prefer, "parts": parts,
                   "from_measure": from_measure, "to_measure": to_measure},
                  lambda s: ops.respell(s, prefer, parts, from_measure, to_measure))


def set_rehearsal(ctx: RunContext[str], measure: int | None = None,
                  mark: str | None = None, remove: bool = False,
                  move_to: int | None = None, reletter: bool = False) -> dict:
    """Add, remove, move or re-letter rehearsal marks.

    measure=9 adds one at bar 9, lettered with the next free letter unless you pass
    mark='C'. remove=True takes the mark at that bar off; move_to=13 moves it there;
    reletter=True re-labels every mark in bar order (A-Z, then AA, BB, CC), which is what
    you want after inserting one in the middle.

    Marks are written to EVERY part, so extracted parts keep them; the combined score
    draws each one once. To change how big a mark is or where it sits, use adjust_element."""
    return _apply(ctx.deps, "set-rehearsal",
                  {"measure": measure, "mark": mark, "remove": remove,
                   "move_to": move_to, "reletter": reletter},
                  lambda s: ops.set_rehearsal(s, measure=measure, mark=mark,
                                              remove=remove, move_to=move_to,
                                              reletter=reletter))


def clean_accidentals(ctx: RunContext[str], parts: list[str] | None = None) -> dict:
    """Hide accidentals that the key signature already implies, so the part reads cleanly.

    Use this when a reader says there are too many accidentals, that accidentals are
    "already in the key signature", or that a part is cluttered or hard to read. Each part
    is judged by the key signature ON ITS OWN STAFF, so a transposing instrument (an E-flat
    alto saxophone, a B-flat clarinet) is judged by its WRITTEN key, not concert pitch.

    Display only: no pitch, no spelling and no key signature changes. Accidentals that are
    genuinely needed -- outside the key, or cancelling an earlier one in the bar -- are kept.
    Every op that changes pitches already runs this, so you rarely need it after your own
    edits; it is for cleaning up material that arrived cluttered."""
    return _apply(ctx.deps, "clean-accidentals", {"parts": parts},
                  lambda s: ops.normalize_accidentals(s, parts))


def set_accidental(ctx: RunContext[str], elements: list[str],
                   show: bool | None = None, add: str | None = None,
                   remove: bool = False, color: str | None = None) -> dict:
    """Add, remove, show, hide or colour the accidentals on particular notes.

    `elements` are addresses like 's1/m15/l1/note#3' (staff/measure/layer/kind#ordinal) --
    pass exactly the ones the context gives you for a selection, unchanged.

    Two of these change the MUSIC:
      add='sharp'|'flat'|'natural'|'double-sharp'|'double-flat' gives the note that
        accidental, which CHANGES ITS PITCH
      remove=True takes the accidental off, which also CHANGES ITS PITCH

    Three change only the DISPLAY, never the pitch:
      show=True  forces the glyph to be drawn (a courtesy accidental)
      show=False stops it being drawn
      color='#CC4125' draws it in that colour; color='none' clears it

    To clean up a whole part rather than named notes, use clean_accidentals."""
    return _apply(ctx.deps, "set-accidental",
                  {"elements": elements, "show": show, "add": add,
                   "remove": remove, "color": color},
                  lambda s: ops.set_accidental(s, elements, show=show, add=add,
                                               remove=remove, color=color))


def change_clef(ctx: RunContext[str], part: str, clef: str, from_measure: int = 1) -> dict:
    """Set a part's clef (treble, bass, alto, tenor, treble8vb, bass8vb) from a given measure."""
    return _apply(ctx.deps, "change-clef", {"part": part, "clef": clef},
                  lambda s: ops.change_clef(ops.find_parts(s, [part])[0], clef, from_measure))


def change_instrument(ctx: RunContext[str], part: str, to_instrument: str) -> dict:
    """Reassign a part to another instrument: converts transposition, octave-fits the line to the
    instrument's range, sets the idiomatic clef, and reports remaining out-of-range notes."""
    return _apply(ctx.deps, "change-instrument", {"part": part, "to": to_instrument},
                  lambda s: ops.change_instrument(ops.find_parts(s, [part])[0], to_instrument))


def rename_part(ctx: RunContext[str], part: str, name: str, abbreviation: str | None = None) -> dict:
    """Rename a part (label only, no musical change)."""
    return _apply(ctx.deps, "rename-part", {"part": part, "name": name},
                  lambda s: ops.rename_part(ops.find_parts(s, [part])[0], name, abbreviation))


def check_range(ctx: RunContext[str], part: str, instrument: str | None = None) -> dict:
    """List notes outside an instrument's range (the part's own instrument, or the named one). Read-only."""
    try:
        from music21 import instrument as m21instrument
        score = _latest(ctx.deps)
        p = ops.find_parts(score, [part])[0]
        cls = (type(m21instrument.fromString(instrument)).__name__ if instrument
               else type(p.getInstrument(returnDefault=False)).__name__)
        if cls not in ops.RANGES:
            return {"ok": False, "error": f"No range data for '{cls}'. Known: {sorted(ops.RANGES)}"}
        return {"part": ops.part_label(p), "instrument": cls,
                "violations": ops.range_violations(p, cls)}
    except Exception as e:
        return {"ok": False, "error": f"{type(e).__name__}: {e}"}


def octave_shift(ctx: RunContext[str], part: str, octaves: int,
                 from_measure: int, to_measure: int) -> dict:
    """Shift a part by whole octaves within an inclusive measure range."""
    return _apply(ctx.deps, "octave-shift",
                  {"part": part, "octaves": octaves, "measures": f"{from_measure}-{to_measure}"},
                  lambda s: ops.octave_shift(s, part, octaves, from_measure, to_measure))


def merge_parts(ctx: RunContext[str], parts: list[str], new_name: str, clef: str = "treble") -> dict:
    """Merge several parts losslessly into one staff (each source becomes a voice)."""
    return _apply(ctx.deps, "merge-parts", {"parts": parts, "name": new_name, "clef": clef},
                  lambda s: ops.merge_parts(s, parts, new_name, clef))


def split_bass(ctx: RunContext[str], part: str, bass_name: str, chords_name: str,
               instrument: str | None = None) -> dict:
    """Split a part into a bass staff (lowest pitch per moment, bass clef) and a chords staff (the rest, treble)."""
    return _apply(ctx.deps, "split-bass", {"part": part},
                  lambda s: ops.split_bass(s, part, bass_name, chords_name, instrument))


def absorb_part(ctx: RunContext[str], source: str, target: str, rules: dict | None = None) -> dict:
    """Fold a chordal part into a melodic part as a second voice under the melody.
    Optional rules override: below_melody(bool), drop_doubling(bool), min_pitch(str), max_span(int)."""
    return _apply(ctx.deps, "absorb-part", {"source": source, "target": target, "rules": rules},
                  lambda s: ops.absorb_part(s, source, target, rules))


def flatten_voices(ctx: RunContext[str], part: str) -> dict:
    """Collapse a multi-voice staff into one voice of chords (piano right-hand style)."""
    return _apply(ctx.deps, "flatten-voices", {"part": part},
                  lambda s: ops.flatten_voices(s, part))


def consolidate_ties(ctx: RunContext[str], parts: list[str]) -> dict:
    """Merge runs of tied same-pitch notes into single longer notes (notational cleanup)."""
    return _apply(ctx.deps, "consolidate-ties", {"parts": parts},
                  lambda s: ops.consolidate_ties(s, parts))


def limit_part(ctx: RunContext[str], part: str, max_pitch: str | None = None,
               monophonic: bool = False) -> dict:
    """Enforce playability limits on a part, always dropping higher notes: a pitch ceiling and/or monophony."""
    return _apply(ctx.deps, "limit-part", {"part": part, "max_pitch": max_pitch, "monophonic": monophonic},
                  lambda s: ops.limit_part(s, part, max_pitch, monophonic))


def simplify_repeats(ctx: RunContext[str], part: str) -> dict:
    """Collapse measures that only restate one pitch class (octave jumps/repeats) to a downbeat note + rests."""
    return _apply(ctx.deps, "simplify-repeats", {"part": part},
                  lambda s: ops.simplify_repeats(s, part))


def analyze_harmony(ctx: RunContext[str], parts: list[str] | None = None) -> dict:
    """Per-measure harmony analysis: ranked chord candidates per bar with the downbeat bass note. Read-only;
    you adjudicate the final chart (prefer functional readings, name secondary dominants literally)."""
    try:
        return ops.analyze_harmony(_latest(ctx.deps), parts)
    except Exception as e:
        return {"ok": False, "error": f"{type(e).__name__}: {e}"}


def set_chords(ctx: RunContext[str], part: str, chords: list[dict]) -> dict:
    """Write chord symbols onto a part: [{"measure": 1, "symbol": "Fm"}, ...].
    Qualities: '', m, 7, m7, maj7, m7b5, 6, m6, dim, dim7, aug; roots may carry b/#."""
    return _apply(ctx.deps, "set-chords", {"part": part, "count": len(chords)},
                  lambda s: ops.set_chord_symbols(s, part, chords))


def chart_style(ctx: RunContext[str], part: str) -> dict:
    """Real Book styling for a chord-symbol staff: hide rests, put the names on the staff."""
    return _apply(ctx.deps, "chart-style", {"part": part},
                  lambda s: ops.chart_style(s, part))


def pull_part(ctx: RunContext[str], from_ref: str, part: str, as_name: str | None = None,
              replace: str | None = None, measures: str | None = None) -> dict:
    """Bring a part (or 'A-B' measure range, requires replace) from a source ('src:s01') or a
    historical version ('v007') into the arrangement."""
    def fn(s):
        from music21 import converter
        if from_ref.startswith("src:"):
            path = workspace.source_path(ctx.deps, from_ref[4:])
        else:
            path = workspace.resolve_path(ctx.deps, from_ref)
        src_score = converter.parse(str(path), forceSource=True)
        rng = None
        if measures:
            a, b = measures.split("-")
            rng = (int(a), int(b))
        return ops.pull_part(s, src_score, part, as_name, replace, rng)
    return _apply(ctx.deps, "pull-part",
                  {"from": from_ref, "part": part, "replace": replace, "measures": measures}, fn)


def set_structure(ctx: RunContext[str], kind: str, measure: int | None = None,
                  to_measure: int | None = None, number: int | None = None,
                  times: int | None = None, remove: bool = False,
                  move_to: int | None = None) -> dict:
    """Add, remove or move a repeat sign, a volta (1st/2nd ending) or a
    navigation mark. kind is one of: repeat-start, repeat-end, repeat-both,
    volta, segno, coda, fine, da-capo, da-capo-al-fine, da-capo-al-coda,
    dal-segno, dal-segno-al-fine, dal-segno-al-coda. A volta needs measure and
    to_measure and a number; a repeat-end can take times. Set remove=True to
    take one off, or move_to to shift it to another measure."""
    def fn(s):
        return ops.set_structure(s, kind, measure=measure, to_measure=to_measure,
                                 number=number, times=times, remove=remove,
                                 move_to=move_to)
    return _apply(ctx.deps, "set-structure",
                  {"kind": kind, "measure": measure, "remove": remove}, fn)


def adjust_element(ctx: RunContext[str], part: str, measure: int | None = None,
                   kind: str = "harm", ordinal: int = 0, size: float | None = None,
                   offset_x: float | None = None, offset_y: float | None = None,
                   reset: bool = False, all_elements: bool = False) -> dict:
    """Change the size or position of an added element. kind="harm" is a chord
    symbol, kind="diagram" a guitar chord diagram.
    `size` is an absolute point size (12 is the default); `offset_x`/`offset_y`
    nudge it sideways/up in MusicXML tenths, positive y being up. Address one
    with measure (+ ordinal when a bar has several), or pass all_elements=True
    for every chord symbol in the part. reset=True puts them back."""
    def fn(s):
        return ops.adjust_element(s, part, kind=kind, measure=measure, ordinal=ordinal,
                                  size=size, offset_x=offset_x, offset_y=offset_y,
                                  reset=reset, all_elements=all_elements)
    return _apply(ctx.deps, "adjust-element",
                  {"part": part, "kind": kind, "measure": measure, "size": size,
                   "reset": reset}, fn)


def guitar_tablature(ctx: RunContext[str], part: str, tuning: str = "EADGBE",
                     capo: int = 0, clear: bool = False) -> dict:
    """Write guitar tablature under a part: a fret number per note on a
    six-line tab staff, at the lowest position that plays it. `tuning` is
    EADGBE (standard), DADGAD or DADGBE (drop D); `capo` is the fret the capo
    sits on. Notes the tuning cannot play are reported, and so is any bar where
    a chord forced the hand higher up the neck. `clear` removes the tab."""
    def fn(s):
        return ops.guitar_tab(s, _part(s, part), tuning, capo=capo, clear=clear)
    return _apply(ctx.deps, "guitar-tab",
                  {"part": part, "tuning": tuning, "capo": capo, "clear": clear}, fn)


def guitar_chord_diagrams(ctx: RunContext[str], part: str, tuning: str = "EADGBE",
                          clear: bool = False,
                          shapes: list[str] | None = None) -> dict:
    """Draw a guitar chord diagram above every chord symbol already on a part:
    the grid, the dots, the barre, the nut, the row of finger numbers over it,
    and a "5 fr." label when the shape sits up the neck. `tuning` is EADGBE
    (standard), DADGAD or DADGBE (drop D). Chords with no playable shape are
    reported. `shapes` pins chords to shapes of the player's choosing, ahead of
    the conventional chart -- ["A7=x02020"] asks for the open A7 rather than
    the fifth-fret barre. `clear` removes the diagrams.
    Size and position are `adjust_element`'s business, with kind="diagram"."""
    def fn(s):
        return ops.chord_diagrams(s, _part(s, part), tuning, clear=clear,
                                  shapes=ops.parse_shape_overrides(shapes))
    return _apply(ctx.deps, "chord-diagrams",
                  {"part": part, "tuning": tuning, "clear": clear,
                   "shape": shapes}, fn)


def penny_whistle_fingerings(ctx: RunContext[str], part: str, whistle: str = "D",
                             clear: bool = False) -> dict:
    """Write penny-whistle fingerings under every note of a part, as stacked
    hole diagrams in the notation (X covered, O open, / half, + overblown).
    `whistle` is the instrument's key (D by default). `clear` removes them."""
    def fn(s):
        return ops.whistle_fingerings(s, _part(s, part), whistle, clear=clear)
    return _apply(ctx.deps, "whistle-fingerings",
                  {"part": part, "whistle": whistle, "clear": clear}, fn)


def set_metadata(ctx: RunContext[str], title: str | None = None,
                 composer: str | None = None, arranger: str | None = None) -> dict:
    """Set the arrangement's title (engraved at the top of the page AND its name
    in the library -- one value, not two), its composer or its arranger.
    An empty string clears a credit."""
    try:
        return workspace.set_score_metadata(ctx.deps, title=title, composer=composer,
                                            arranger=arranger)
    except Exception as e:
        return {"ok": False, "error": f"{type(e).__name__}: {e}"}


def assign_to_piece(ctx: RunContext[str], piece_name: str) -> dict:
    """File this arrangement under a piece, creating it if needed."""
    try:
        return workspace.assign_score_to_piece(ctx.deps, piece_name, create_if_missing=True)
    except Exception as e:
        return {"ok": False, "error": f"{type(e).__name__}: {e}"}


TOOLS = [get_score_info, list_versions, keep_parts, remove_parts, transpose,
         transpose_elements,
         respell, clean_accidentals, set_accidental, set_rehearsal,
         change_clef, change_instrument, rename_part, check_range, octave_shift,
         merge_parts, split_bass, absorb_part, flatten_voices, consolidate_ties,
         limit_part, simplify_repeats, analyze_harmony, set_chords, chart_style,
         pull_part, set_metadata, penny_whistle_fingerings, guitar_chord_diagrams,
         guitar_tablature,
         set_structure,
         adjust_element,
         assign_to_piece]


def resolve_model(alias_or_string: str | None) -> str:
    name = alias_or_string or DEFAULT_MODEL
    return MODELS.get(name, name)  # unknown alias = raw pydantic-ai model string


def run_chat(slug: str, message: str, model: str | None = None,
             history_json: str | None = None) -> dict:
    """One chat turn. Returns the reply, serialized history for the next turn,
    and the score's new latest version."""
    from pydantic_ai.messages import ModelMessagesTypeAdapter

    workspace.load_meta(slug)  # validate score exists before spending tokens
    agent = Agent(resolve_model(model), deps_type=str, instructions=INSTRUCTIONS,
                  tools=TOOLS, retries=2)
    history = ModelMessagesTypeAdapter.validate_json(history_json) if history_json else None
    result = agent.run_sync(message, deps=slug, message_history=history)
    usage = result.usage if not callable(result.usage) else result.usage()
    return {
        "reply": result.output,
        "model": resolve_model(model),
        "usage": {k: getattr(usage, k, None) for k in
                  ("input_tokens", "output_tokens", "requests")},
        "history": result.all_messages_json().decode(),
        "latest": workspace.load_meta(slug).get("latest"),
    }
