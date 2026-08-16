"""scor — the Scoranger score engine CLI.

Every command prints JSON to stdout. Mutating commands create a new immutable
version of the score; nothing is edited in place.
"""

import argparse
import json
import sys
from pathlib import Path

from . import ops, workspace


def _load(slug: str, version: str | None):
    from music21 import converter
    path = workspace.resolve_path(slug, version)
    return converter.parse(str(path), forceSource=True)


def _load_ref(slug: str, ref: str):
    """Load a document by reference: 'vNNN' (version) or 'src:sNN' (source)."""
    from music21 import converter
    if ref.startswith("src:"):
        path = workspace.source_path(slug, ref[4:])
    else:
        path = workspace.resolve_path(slug, ref)
    return converter.parse(str(path), forceSource=True)


def _split_parts(s: str) -> list[str]:
    parts = [x.strip() for x in s.split(",") if x.strip()]
    if not parts:
        raise ValueError("--parts is empty")
    return parts


def _emit(payload: dict) -> None:
    print(json.dumps(payload, indent=2))


def _mutate(slug: str, score, op: str, args: dict, details) -> None:
    entry = workspace.add_version(slug, score, op, args)
    _emit({"score": slug, "op": op, "new_version": entry["id"], "details": details,
           "file": str(workspace.score_dir(slug) / entry["file"])})


def cmd_import(a):
    from music21 import converter
    src = Path(a.file).expanduser()
    if not src.exists():
        raise FileNotFoundError(f"No such file: {src}")
    score = converter.parse(str(src), forceSource=True)
    name = a.name or (score.metadata.title if score.metadata and score.metadata.title else src.stem)
    if score.metadata is not None and not score.metadata.title:
        score.metadata.title = name
    slug, entry = workspace.create_score(name, score, op="import", args={"source": str(src)})
    _emit({"score": slug, "name": name, "version": entry["id"], "info": ops.info(score)})


def cmd_list(a):
    _emit(workspace.rebuild_manifest())


def cmd_info(a):
    _emit(ops.info(_load(a.score, a.version)))


def cmd_versions(a):
    meta = workspace.load_meta(a.score)
    _emit({"score": a.score, "name": meta["name"], "versions": meta["versions"]})


def cmd_keep_parts(a):
    score = _load(a.score, None)
    removed = ops.keep_parts(score, _split_parts(a.parts))
    _mutate(a.score, score, "keep-parts", {"parts": a.parts},
            {"kept": ops.list_part_labels(score), "removed": removed})


def cmd_remove_parts(a):
    score = _load(a.score, None)
    removed = ops.remove_parts(score, _split_parts(a.parts))
    _mutate(a.score, score, "remove-parts", {"parts": a.parts},
            {"removed": removed, "remaining": ops.list_part_labels(score)})


def cmd_transpose(a):
    score = _load(a.score, None)
    names = _split_parts(a.parts) if a.parts else None
    details = ops.transpose(score, a.interval, names)
    _mutate(a.score, score, "transpose", {"interval": a.interval, "parts": a.parts}, details)


def cmd_respell(a):
    score = _load(a.score, None)
    names = _split_parts(a.parts) if a.parts else None
    details = ops.respell(score, a.prefer, names)
    _mutate(a.score, score, "respell", {"prefer": a.prefer, "parts": a.parts}, details)


def cmd_change_clef(a):
    score = _load(a.score, None)
    part = ops.find_parts(score, [a.part])[0]
    details = ops.change_clef(part, a.clef, a.from_measure)
    _mutate(a.score, score, "change-clef", {"part": a.part, "clef": a.clef}, details)


def cmd_change_instrument(a):
    score = _load(a.score, None)
    part = ops.find_parts(score, [a.part])[0]
    details = ops.change_instrument(part, a.to)
    _mutate(a.score, score, "change-instrument", {"part": a.part, "to": a.to}, details)


def cmd_merge_parts(a):
    score = _load(a.score, None)
    details = ops.merge_parts(score, _split_parts(a.parts), a.name, a.clef)
    _mutate(a.score, score, "merge-parts", {"parts": a.parts, "name": a.name, "clef": a.clef}, details)


def cmd_split_bass(a):
    score = _load(a.score, None)
    details = ops.split_bass(score, a.part, a.bass_name, a.chords_name, a.instrument)
    _mutate(a.score, score, "split-bass",
            {"part": a.part, "bass_name": a.bass_name, "chords_name": a.chords_name}, details)


def cmd_consolidate_ties(a):
    score = _load(a.score, None)
    details = ops.consolidate_ties(score, _split_parts(a.parts))
    _mutate(a.score, score, "consolidate-ties", {"parts": a.parts}, details)


def cmd_limit_part(a):
    score = _load(a.score, None)
    details = ops.limit_part(score, a.part, a.max_pitch, a.monophonic)
    _mutate(a.score, score, "limit-part",
            {"part": a.part, "max_pitch": a.max_pitch, "monophonic": a.monophonic}, details)


def cmd_rename_part(a):
    score = _load(a.score, None)
    part = ops.find_parts(score, [a.part])[0]
    details = ops.rename_part(part, a.name, a.abbreviation)
    _mutate(a.score, score, "rename-part", {"part": a.part, "name": a.name}, details)


def cmd_check_range(a):
    score = _load(a.score, a.version)
    part = ops.find_parts(score, [a.part])[0]
    if a.instrument:
        from music21 import instrument as m21instrument
        cls = type(m21instrument.fromString(a.instrument)).__name__
    else:
        instr = part.getInstrument(returnDefault=False)
        cls = type(instr).__name__ if instr else None
    if cls not in ops.RANGES:
        raise ValueError(f"No range data for '{cls}'. Known: {sorted(ops.RANGES)} (pass --instrument)")
    _emit({"part": ops.part_label(part), "instrument": cls, "range": list(ops.RANGES[cls]),
           "violations": ops.range_violations(part, cls)})


def cmd_absorb_part(a):
    score = _load(a.score, a.from_version)
    rules = json.loads(a.rules) if a.rules else None
    details = ops.absorb_part(score, a.source, a.target, rules)
    _mutate(a.score, score, "absorb-part",
            {"source": a.source, "target": a.target, "rules": rules}, details)


def cmd_strip_notes(a):
    score = _load(a.score, None)
    details = ops.strip_notes(score, a.part)
    _mutate(a.score, score, "strip-notes", {"part": a.part}, details)


def cmd_add_source(a):
    from music21 import converter
    src = Path(a.file).expanduser()
    if not src.exists():
        raise FileNotFoundError(f"No such file: {src}")
    m21_score = converter.parse(str(src), forceSource=True)
    name = a.name or src.stem
    doc = workspace.add_source(a.score, m21_score, name, origin=str(src))
    _emit({"score": a.score, "source": doc["id"], "name": name,
           "parts": [p["name"] for p in (doc.get("parts") or [])]})


def cmd_pull_part(a):
    score = _load(a.score, None)
    src_score = _load_ref(a.score, getattr(a, "from"))
    measures = None
    if a.measures:
        m0, m1 = a.measures.split("-")
        measures = (int(m0), int(m1))
    details = ops.pull_part(score, src_score, a.part, a.as_name, a.replace, measures)
    _mutate(a.score, score, "pull-part",
            {"from": getattr(a, "from"), "part": a.part, "replace": a.replace,
             "measures": a.measures}, details)


def cmd_simplify_repeats(a):
    score = _load(a.score, None)
    details = ops.simplify_repeats(score, a.part, a.note_length)
    _mutate(a.score, score, "simplify-repeats", {"part": a.part}, details)


def cmd_octave_shift(a):
    score = _load(a.score, None)
    details = ops.octave_shift(score, a.part, a.octaves, a.from_measure, a.to_measure)
    _mutate(a.score, score, "octave-shift",
            {"part": a.part, "octaves": a.octaves, "measures": f"{a.from_measure}-{a.to_measure}"}, details)


def cmd_rebuild_part(a):
    score = _load(a.score, None)
    src = _load(a.score, a.source_version)
    rules = json.loads(a.rules) if a.rules else None
    details = ops.rebuild_part(score, a.part, src, a.base, a.overlay, rules)
    _mutate(a.score, score, "rebuild-part",
            {"part": a.part, "source_version": a.source_version,
             "base": a.base, "overlay": a.overlay}, details)


def cmd_flatten_voices(a):
    score = _load(a.score, a.from_version)
    details = ops.flatten_voices(score, a.part)
    _mutate(a.score, score, "flatten-voices", {"part": a.part}, details)


def cmd_chart_style(a):
    score = _load(a.score, None)
    details = ops.chart_style(score, a.part, a.symbol_y)
    _mutate(a.score, score, "chart-style", {"part": a.part}, details)


def cmd_analyze(a):
    score = _load(a.score, a.version)
    names = _split_parts(a.parts) if a.parts else None
    _emit(ops.analyze_harmony(score, names))


def cmd_set_chords(a):
    score = _load(a.score, None)
    chords = json.loads(Path(a.json).read_text())
    details = ops.set_chord_symbols(score, a.part, chords)
    _mutate(a.score, score, "set-chords", {"part": a.part, "count": len(chords)}, details)


def cmd_delete_score(a):
    workspace.delete_score(a.score)
    _emit({"deleted": a.score})


def cmd_serve(a):
    from . import server
    server.serve(a.port, a.host)


def cmd_export(a):
    out = Path(a.out).expanduser()
    out.parent.mkdir(parents=True, exist_ok=True)
    parts = _split_parts(a.parts) if a.parts else None
    if a.format == "pdf":
        from . import render
        meta = workspace.load_meta(a.score)
        title = meta["name"] + (f" — {', '.join(parts)}" if parts else "")
        details = render.render_pdf(workspace.resolve_path(a.score, a.version), out,
                                    parts=parts, title=title)
        _emit({"score": a.score, "format": "pdf", **details})
        return
    score = _load(a.score, a.version)
    if parts:
        ops.keep_parts(score, parts)
    score.write(a.format, fp=str(out))
    _emit({"score": a.score, "format": a.format, "parts": parts or "all", "out": str(out)})


def main() -> None:
    p = argparse.ArgumentParser(prog="scor", description="Scoranger score engine")
    sub = p.add_subparsers(dest="command", required=True)

    s = sub.add_parser("import", help="Import a score file into the workspace")
    s.add_argument("file")
    s.add_argument("--name")
    s.set_defaults(fn=cmd_import)

    s = sub.add_parser("list", help="List all scores")
    s.set_defaults(fn=cmd_list)

    s = sub.add_parser("info", help="Describe a score's parts and structure")
    s.add_argument("score")
    s.add_argument("--version")
    s.set_defaults(fn=cmd_info)

    s = sub.add_parser("versions", help="Version history of a score")
    s.add_argument("score")
    s.set_defaults(fn=cmd_versions)

    s = sub.add_parser("keep-parts", help="Keep only the named parts")
    s.add_argument("score")
    s.add_argument("--parts", required=True, help='Comma-separated, e.g. "Violin I,Viola"')
    s.set_defaults(fn=cmd_keep_parts)

    s = sub.add_parser("remove-parts", help="Remove the named parts")
    s.add_argument("score")
    s.add_argument("--parts", required=True)
    s.set_defaults(fn=cmd_remove_parts)

    s = sub.add_parser("transpose", help="Transpose the score (or named parts)")
    s.add_argument("score")
    s.add_argument("--interval", required=True, help="e.g. M2, m3, P4, -M2, P8")
    s.add_argument("--parts")
    s.set_defaults(fn=cmd_transpose)

    s = sub.add_parser("respell", help="Respell accidentals enharmonically (flats <-> sharps)")
    s.add_argument("score")
    s.add_argument("--prefer", choices=["flats", "sharps"], default="flats")
    s.add_argument("--parts")
    s.set_defaults(fn=cmd_respell)

    s = sub.add_parser("change-clef", help="Set a part's clef")
    s.add_argument("score")
    s.add_argument("--part", required=True)
    s.add_argument("--clef", required=True, help=f"One of: {', '.join(sorted(ops.CLEFS))}")
    s.add_argument("--from-measure", type=int, default=1)
    s.set_defaults(fn=cmd_change_clef)

    s = sub.add_parser("change-instrument", help="Reassign a part to another instrument (range + clef aware)")
    s.add_argument("score")
    s.add_argument("--part", required=True)
    s.add_argument("--to", required=True, help='e.g. Viola, Clarinet, "French Horn"')
    s.set_defaults(fn=cmd_change_instrument)

    s = sub.add_parser("merge-parts", help="Merge parts into one staff (each source becomes a voice; lossless)")
    s.add_argument("score")
    s.add_argument("--parts", required=True, help='Comma-separated sources in voice order, e.g. "Viola,Violoncello"')
    s.add_argument("--name", required=True, help="Name for the merged part")
    s.add_argument("--clef", default="treble")
    s.set_defaults(fn=cmd_merge_parts)

    s = sub.add_parser("split-bass", help="Split a part into bass-note staff (lowest pitch) + chords staff (the rest)")
    s.add_argument("score")
    s.add_argument("--part", required=True)
    s.add_argument("--bass-name", required=True)
    s.add_argument("--chords-name", required=True)
    s.add_argument("--instrument", help="Instrument to stamp on both new staves, e.g. Accordion")
    s.set_defaults(fn=cmd_split_bass)

    s = sub.add_parser("consolidate-ties", help="Merge tied same-pitch runs into single longer notes (notational cleanup)")
    s.add_argument("score")
    s.add_argument("--parts", required=True)
    s.set_defaults(fn=cmd_consolidate_ties)

    s = sub.add_parser("limit-part", help="Enforce playability limits on a part (drops higher notes, keeps lower)")
    s.add_argument("score")
    s.add_argument("--part", required=True)
    s.add_argument("--max-pitch", help="Remove notes strictly above this pitch, e.g. C4")
    s.add_argument("--monophonic", action="store_true", help="One note at a time: chords -> lowest note, overlaps -> keep lower")
    s.set_defaults(fn=cmd_limit_part)

    s = sub.add_parser("rename-part", help="Rename a part (label only; no musical change)")
    s.add_argument("score")
    s.add_argument("--part", required=True, help="Part name or index like '#0'")
    s.add_argument("--name", required=True)
    s.add_argument("--abbreviation")
    s.set_defaults(fn=cmd_rename_part)

    s = sub.add_parser("check-range", help="List notes outside an instrument's range")
    s.add_argument("score")
    s.add_argument("--part", required=True)
    s.add_argument("--instrument", help="Check against this instrument instead of the part's own")
    s.add_argument("--version")
    s.set_defaults(fn=cmd_check_range)

    s = sub.add_parser("absorb-part", help="Fold a chordal part into a melodic part as voice 2, rule-governed")
    s.add_argument("score")
    s.add_argument("--source", required=True)
    s.add_argument("--target", required=True)
    s.add_argument("--rules", help=f"JSON overrides of {ops.ABSORB_DEFAULT_RULES}")
    s.add_argument("--from-version", help="Apply to this version instead of latest (branch from history)")
    s.set_defaults(fn=cmd_absorb_part)

    s = sub.add_parser("strip-notes", help="Empty a part of notes, keeping chord symbols (names-only staff)")
    s.add_argument("score")
    s.add_argument("--part", required=True)
    s.set_defaults(fn=cmd_strip_notes)

    s = sub.add_parser("add-source", help="Attach another found edition/tab of the piece as a reference source")
    s.add_argument("score")
    s.add_argument("file")
    s.add_argument("--name", help="Label for this source, e.g. 'MuseScore tab version'")
    s.set_defaults(fn=cmd_add_source)

    s = sub.add_parser("pull-part", help="Bring a part (or measure range) from a source or old version into the score")
    s.add_argument("score")
    s.add_argument("--from", required=True, dest="from", metavar="REF",
                   help="Where to pull from: 'vNNN' (history) or 'src:sNN' (source)")
    s.add_argument("--part", required=True, help="Part name in the source document")
    s.add_argument("--as", dest="as_name", help="Rename the pulled part")
    s.add_argument("--replace", help="Existing part to replace (required with --measures)")
    s.add_argument("--measures", help="Only this range, e.g. 21-36")
    s.set_defaults(fn=cmd_pull_part)

    s = sub.add_parser("simplify-repeats", help="Collapse single-pitch-class measures (octave jumps/repeats) to downbeat note + rests")
    s.add_argument("score")
    s.add_argument("--part", required=True)
    s.add_argument("--note-length", type=float, default=1.0)
    s.set_defaults(fn=cmd_simplify_repeats)

    s = sub.add_parser("octave-shift", help="Shift a part by octaves within a measure range")
    s.add_argument("score")
    s.add_argument("--part", required=True)
    s.add_argument("--octaves", type=int, required=True, help="e.g. -1 for down an octave")
    s.add_argument("--from-measure", type=int, required=True)
    s.add_argument("--to-measure", type=int, required=True)
    s.set_defaults(fn=cmd_octave_shift)

    s = sub.add_parser("rebuild-part", help="Replace a part with a base part from history + rule-kept overlay runs")
    s.add_argument("score")
    s.add_argument("--part", required=True, help="Target part in the current version")
    s.add_argument("--source-version", required=True, help="Version to take base/overlay parts from")
    s.add_argument("--base", required=True)
    s.add_argument("--overlay")
    s.add_argument("--rules", help=f"JSON overrides of {ops.REBUILD_DEFAULT_RULES}")
    s.set_defaults(fn=cmd_rebuild_part)

    s = sub.add_parser("flatten-voices", help="Collapse a multi-voice staff into one voice of chords (piano-RH style)")
    s.add_argument("score")
    s.add_argument("--part", required=True)
    s.add_argument("--from-version", help="Apply to this version instead of latest")
    s.set_defaults(fn=cmd_flatten_voices)

    s = sub.add_parser("chart-style", help="Real Book styling for a chord staff: hide rests, names on the staff")
    s.add_argument("score")
    s.add_argument("--part", required=True)
    s.add_argument("--symbol-y", type=float, default=-25.0, help="Vertical position in tenths (-20 = middle line)")
    s.set_defaults(fn=cmd_chart_style)

    s = sub.add_parser("analyze", help="Per-measure harmony analysis with ranked chord candidates (read-only)")
    s.add_argument("score")
    s.add_argument("--parts", help="Restrict analysis to these parts (default: all)")
    s.add_argument("--version")
    s.set_defaults(fn=cmd_analyze)

    s = sub.add_parser("set-chords", help="Write chord symbols onto a part from a JSON chart")
    s.add_argument("score")
    s.add_argument("--part", required=True)
    s.add_argument("--json", required=True, help='Path to [{"measure":1,"symbol":"Fm"},...]')
    s.set_defaults(fn=cmd_set_chords)

    s = sub.add_parser("delete-score", help="Delete a score, its versions, and its files (irreversible)")
    s.add_argument("score")
    s.set_defaults(fn=cmd_delete_score)

    s = sub.add_parser("serve", help="Run the local engine API (viewer uploads, exports, chat, iOS app)")
    s.add_argument("--port", type=int, default=8765)
    s.add_argument("--host", default="127.0.0.1",
                   help="Bind address; use 0.0.0.0 to allow the iPad app on your LAN")
    s.set_defaults(fn=cmd_serve)

    s = sub.add_parser("export", help="Export a version to a file (optionally only some parts)")
    s.add_argument("score")
    s.add_argument("--format", choices=["musicxml", "midi", "pdf"], default="musicxml")
    s.add_argument("--out", required=True)
    s.add_argument("--version")
    s.add_argument("--parts", help="Only include these parts (comma-separated)")
    s.set_defaults(fn=cmd_export)

    a = p.parse_args()
    try:
        a.fn(a)
    except Exception as e:
        print(json.dumps({"error": f"{type(e).__name__}: {e}"}), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
