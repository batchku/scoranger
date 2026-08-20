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
    "kimi": "openrouter:moonshotai/kimi-k3:exacto",              # $3.00/$15 — :exacto = curated tool-call routing
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


def respell(ctx: RunContext[str], prefer: str = "flats", parts: list[str] | None = None,
            from_measure: int | None = None, to_measure: int | None = None) -> dict:
    """Respell accidentals enharmonically: prefer='flats' turns G# into Ab (right for flat keys
    like F minor); prefer='sharps' does the reverse. Key signatures are untouched. Set
    from_measure/to_measure (inclusive) to respell only that measure range."""
    return _apply(ctx.deps, "respell",
                  {"prefer": prefer, "parts": parts,
                   "from_measure": from_measure, "to_measure": to_measure},
                  lambda s: ops.respell(s, prefer, parts, from_measure, to_measure))


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


def assign_to_piece(ctx: RunContext[str], piece_name: str) -> dict:
    """File this arrangement under a piece, creating it if needed."""
    try:
        return workspace.assign_score_to_piece(ctx.deps, piece_name, create_if_missing=True)
    except Exception as e:
        return {"ok": False, "error": f"{type(e).__name__}: {e}"}


TOOLS = [get_score_info, list_versions, keep_parts, remove_parts, transpose,
         respell, change_clef, change_instrument, rename_part, check_range, octave_shift,
         merge_parts, split_bass, absorb_part, flatten_voices, consolidate_ties,
         limit_part, simplify_repeats, analyze_harmony, set_chords, chart_style,
         pull_part, assign_to_piece]


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
