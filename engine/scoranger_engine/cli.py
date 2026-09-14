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
    # resolve_notation_path, not resolve_path: a PDF arrangement must be told
    # apart here, or music21 fails deep in a parser with nothing useful to say
    path = workspace.resolve_notation_path(slug, version)
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
    # both names: `new_version` is the identity to pass back to any other
    # command, `new_version_label` is the `v012` to put in a sentence
    _emit({"score": slug, "op": op, "new_version": entry["id"],
           "new_version_label": workspace.version_label(entry), "details": details,
           "file": str(workspace.score_dir(slug) / entry["file"])})


def cmd_import(a):
    from music21 import converter
    src = Path(a.file).expanduser()
    if not src.exists():
        raise FileNotFoundError(f"No such file: {src}")
    score = converter.parse(str(src), forceSource=True)
    name = a.name or ops.engraved_title(score) or src.stem
    # music21 seeds the movement title with the file name, extension and all,
    # and that is what Verovio engraves -- so the title is normalized on the way
    # in rather than surfacing as "my-score.mxl" at the top of the page.
    name = ops.clean_imported_metadata(score, name, source_stem=src.stem)["title"]
    slug, entry = workspace.create_score(name, score, op="import", args={"source": str(src)})
    out = {"score": slug, "name": name, "version": entry["id"],
           "version_label": workspace.version_label(entry), "info": ops.info(score)}
    # imperfect sources import and say so; they are never refused
    if entry.get("rhythm_warnings"):
        out["rhythm_warnings"] = entry["rhythm_warnings"]
    _emit(out)


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


def cmd_transpose_diatonic(a):
    score = _load(a.score, None)
    names = _split_parts(a.parts) if a.parts else None
    details = ops.transpose_diatonic(score, a.degrees, names,
                                     a.from_measure, a.to_measure, a.key)
    _mutate(a.score, score, "transpose-diatonic",
            {"degrees": a.degrees, "parts": a.parts, "key": a.key,
             "from_measure": a.from_measure, "to_measure": a.to_measure}, details)


def cmd_transpose_diatonic_elements(a):
    score = _load(a.score, None)
    addresses = [t.strip() for t in a.elements.split(",") if t.strip()]
    details = ops.transpose_diatonic_elements(score, a.degrees, addresses, a.key)
    _mutate(a.score, score, "transpose-diatonic-elements",
            {"degrees": a.degrees, "elements": addresses, "key": a.key}, details)


def cmd_transpose_elements(a):
    score = _load(a.score, None)
    addresses = [t.strip() for t in a.elements.split(",") if t.strip()]
    details = ops.transpose_elements(score, a.interval, addresses)
    _mutate(a.score, score, "transpose-elements",
            {"interval": a.interval, "elements": addresses}, details)


def cmd_clean_accidentals(a):
    score = _load(a.score, None)
    names = _split_parts(a.parts) if a.parts else None
    details = ops.normalize_accidentals(score, names)
    _mutate(a.score, score, "clean-accidentals", {"parts": a.parts}, details)


def cmd_set_accidental(a):
    score = _load(a.score, None)
    addresses = [t.strip() for t in a.elements.split(",") if t.strip()]
    show = True if a.show else (False if a.hide else None)
    details = ops.set_accidental(score, addresses, show=show, add=a.add,
                                 remove=a.remove, color=a.color)
    _mutate(a.score, score, "set-accidental",
            {"elements": addresses, "show": show, "add": a.add,
             "remove": a.remove, "color": a.color}, details)


def cmd_set_rehearsal(a):
    score = _load(a.score, None)
    details = ops.set_rehearsal(score, measure=a.measure, mark=a.mark,
                                remove=a.remove, move_to=a.move_to,
                                reletter=a.reletter)
    _mutate(a.score, score, "set-rehearsal",
            {"measure": a.measure, "mark": a.mark, "remove": a.remove,
             "move_to": a.move_to, "reletter": a.reletter}, details)


def cmd_delete_piece(a):
    workspace.delete_piece(a.piece, with_arrangements=a.with_arrangements)
    _emit({"deleted": a.piece, "arrangements": bool(a.with_arrangements)})


def cmd_duplicate(a):
    score = _load(a.score, None)
    name = a.name or f"{a.score} copy"
    slug, entry = workspace.create_score(name, score, op="duplicate", args={"source": a.score})
    _emit({"score": slug, "version": entry["id"]})


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


def cmd_bulk_import(a):
    from . import bulk

    folder = Path(a.folder).expanduser()
    if not folder.is_dir():
        raise NotADirectoryError(f"No such folder: {folder}")
    manifest = None
    if a.manifest:
        manifest = json.loads(Path(a.manifest).expanduser().read_text())
    names = sorted(p.name for p in folder.iterdir() if p.is_file())
    plan = bulk.plan(names, manifest=manifest)
    if a.commit:
        _emit({"plan": plan, "result": bulk.run(plan, dry_run=False, root=str(folder))})
    else:
        # printed for a person, because the point of the dry run is to be read
        print(bulk.describe(plan), file=sys.stderr)
        _emit({"plan": plan, "result": bulk.run(plan, dry_run=True)})


def cmd_import_book(a):
    src = Path(a.file).expanduser()
    slug, doc = workspace.create_book(a.name or src.stem, src)
    _emit({"book": slug, "name": doc["name"], "pages": doc["pages"]})


def cmd_book_extract(a):
    slug, entry = workspace.extract_from_book(a.book, a.from_page, a.to_page,
                                              a.name, a.piece)
    _emit({"score": slug, "version": entry["id"], "piece": a.piece})


def cmd_books(a):
    _emit({"books": workspace.list_books()})


def cmd_piece_create(a):
    _emit(workspace.create_piece(a.name))


def cmd_piece_assign(a):
    if a.unassign:
        _emit(workspace.assign_score_to_piece(a.score, None))
    else:
        if not a.piece:
            raise ValueError("Pass --piece NAME (or --unassign)")
        _emit(workspace.assign_score_to_piece(a.score, a.piece, create_if_missing=True))


def cmd_piece_rename(a):
    _emit(workspace.rename_piece(a.piece, a.name))


def cmd_rename_score(a):
    _emit(workspace.rename_score(a.score, a.name))


def cmd_move_element(a):
    score = _load(a.score, None)
    details = ops.move_element(score, a.part, a.kind, a.measure,
                               ordinal=a.ordinal, to_measure=a.to_measure,
                               to_offset=a.to_offset)
    _mutate(a.score, score, "move-element",
            {"part": a.part, "kind": a.kind, "measure": a.measure,
             "to_measure": a.to_measure, "to_offset": a.to_offset}, details)


def cmd_duplicate_element(a):
    score = _load(a.score, None)
    details = ops.duplicate_element(score, a.part, a.kind, a.measure,
                                    ordinal=a.ordinal, to_measure=a.to_measure,
                                    to_offset=a.to_offset)
    _mutate(a.score, score, "duplicate-element",
            {"part": a.part, "kind": a.kind, "measure": a.measure,
             "to_measure": a.to_measure, "to_offset": a.to_offset}, details)


def cmd_rename_book(a):
    _emit(workspace.rename_book(a.book, a.name))


def cmd_set_structure(a):
    score = _load(a.score, None)
    details = ops.set_structure(score, a.kind, measure=a.measure,
                                to_measure=a.to_measure, number=a.number,
                                times=a.times, remove=a.remove, move_to=a.move_to)
    _mutate(a.score, score, "set-structure",
            {"kind": a.kind, "measure": a.measure, "remove": a.remove}, details)


def cmd_adjust_element(a):
    score = _load(a.score, None)
    details = ops.adjust_element(score, a.part, kind=a.kind, measure=a.measure,
                                 ordinal=a.ordinal, size=a.size, scale=a.scale,
                                 offset_x=a.offset_x, offset_y=a.offset_y,
                                 reset=a.reset, all_elements=a.all)
    _mutate(a.score, score, "adjust-element",
            {"part": a.part, "kind": a.kind, "measure": a.measure,
             "size": a.size, "reset": a.reset}, details)


def cmd_whistle_fingerings(a):
    score = _load(a.score, None)
    # find_parts, like every other command here: `_part` exists in the app's
    # bridge but never in the CLI, so this op could not be run from the
    # command line at all -- it failed with a NameError before touching a note
    part = ops.find_parts(score, [a.part])[0]
    details = ops.whistle_fingerings(score, part, a.whistle, clear=a.clear)
    _mutate(a.score, score, "whistle-fingerings",
            {"part": a.part, "whistle": a.whistle, "clear": a.clear}, details)


def cmd_guitar_tab(a):
    score = _load(a.score, None)
    part = ops.find_parts(score, [a.part])[0]
    details = ops.guitar_tab(score, part, a.tuning, capo=a.capo, clear=a.clear,
                             position=a.position)
    _mutate(a.score, score, "guitar-tab",
            {"part": a.part, "tuning": a.tuning, "capo": a.capo,
             "clear": a.clear, "position": a.position},
            details)


def cmd_chord_diagrams(a):
    score = _load(a.score, None)
    part = ops.find_parts(score, [a.part])[0]
    shapes = ops.parse_shape_overrides(a.shape)
    details = ops.chord_diagrams(score, part, a.tuning, clear=a.clear,
                                 shapes=shapes)
    _mutate(a.score, score, "chord-diagrams",
            {"part": a.part, "tuning": a.tuning, "clear": a.clear,
             "shape": a.shape}, details)


def cmd_rename_slug(a):
    _emit(workspace.rename_slug(a.score, a.to))


def cmd_set_metadata(a):
    _emit(workspace.set_score_metadata(a.score, title=a.title, composer=a.composer,
                                       arranger=a.arranger))


def cmd_repair_titles(a):
    _emit(workspace.repair_titles(dry_run=not a.apply))


def cmd_set_piece_metadata(a):
    tags = None
    if a.tags is not None:
        tags = [t.strip() for t in a.tags.split(",")] if a.tags.strip() else []
    _emit(workspace.set_piece_metadata(a.piece, composer=a.composer, tags=tags,
                                       arranger=a.arranger))


def cmd_tags(a):
    _emit({"tags": workspace.all_tags()})


def cmd_delete_score(a):
    workspace.delete_score(a.score)
    _emit({"deleted": a.score})


def cmd_serve(a):
    from . import server
    server.serve(a.port, a.host)


def cmd_bundle_export(a):
    from . import bundle
    _emit(bundle.export(a.target, Path(a.out).expanduser(),
                        full_history=a.full_history,
                        ink_dir=Path(a.ink).expanduser() if a.ink else None))


def cmd_bundle_inspect(a):
    from . import bundle
    _emit(bundle.inspect(Path(a.path).expanduser()))


def cmd_bundle_import(a):
    from . import bundle
    _emit(bundle.import_(Path(a.path).expanduser(), into_piece=a.into_piece,
                         ink_dir=Path(a.ink).expanduser() if a.ink else None))


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


def cmd_playback(a):
    out = Path(a.out).expanduser()
    out.parent.mkdir(parents=True, exist_ok=True)
    played, timeline = ops.playback_timeline(_load(a.score, a.version))
    played.write("midi", fp=str(out))
    _emit({"score": a.score, "out": str(out), "timeline": timeline})


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

    s = sub.add_parser("transpose-diatonic",
                       help="Move by SCALE DEGREES, staying in the key "
                            "(a harmony line, not a modulation)")
    s.add_argument("score")
    s.add_argument("--degrees", required=True,
                   help="signed generic interval: -6 is down a sixth, 3 up a third. "
                        "Names work too: 'down a sixth'")
    s.add_argument("--parts")
    s.add_argument("--from-measure", type=int)
    s.add_argument("--to-measure", type=int)
    s.add_argument("--key", help="the key to count degrees in, when the staff "
                                 "carries no signature (e.g. G, e, Bb)")
    s.set_defaults(fn=cmd_transpose_diatonic)

    s = sub.add_parser("transpose-diatonic-elements",
                       help="Move ONLY the named elements by scale degrees, in key")
    s.add_argument("score")
    s.add_argument("--degrees", required=True)
    s.add_argument("--elements", required=True,
                   help="comma-separated addresses, e.g. 's1/m15/l1/note#0'")
    s.add_argument("--key")
    s.set_defaults(fn=cmd_transpose_diatonic_elements)

    s = sub.add_parser("delete-piece", help="Delete a piece (a piece holding nothing cannot exist)")
    s.add_argument("piece")
    s.add_argument("--with-arrangements", action="store_true",
                   help="delete its arrangements too, rather than unfiling them")
    s.set_defaults(fn=cmd_delete_piece)

    s = sub.add_parser("transpose-elements",
                       help="Transpose ONLY the named elements (from a lasso selection)")
    s.add_argument("score")
    s.add_argument("--interval", required=True)
    s.add_argument("--elements", required=True,
                   help="comma-separated addresses, e.g. 's1/m15/l1/note#0,s1/m15/l1/note#1'")
    s.set_defaults(fn=cmd_transpose_elements)

    s = sub.add_parser("set-rehearsal",
                       help="Add, remove, move or re-letter rehearsal marks "
                            "(written to EVERY part)")
    s.add_argument("score")
    s.add_argument("--measure", type=int)
    s.add_argument("--mark", help="the letter; omitted, the next free one is used")
    s.add_argument("--remove", action="store_true")
    s.add_argument("--move-to", dest="move_to", type=int)
    s.add_argument("--reletter", action="store_true",
                   help="re-label every mark in bar order: A-Z then AA, BB")
    s.set_defaults(fn=cmd_set_rehearsal)

    s = sub.add_parser("clean-accidentals",
                       help="Hide accidentals the key signature already implies "
                            "(display only; no pitch changes)")
    s.add_argument("score")
    s.add_argument("--parts", help="default: every part, each judged by its OWN written key")
    s.set_defaults(fn=cmd_clean_accidentals)

    s = sub.add_parser("set-accidental",
                       help="Add, remove, show, hide or colour accidentals on named elements")
    s.add_argument("score")
    s.add_argument("--elements", required=True,
                   help="comma-separated addresses, e.g. 's1/m15/l1/note#0'")
    s.add_argument("--add", choices=sorted(ops.ACCIDENTAL_NAMES),
                   help="give the note this accidental -- CHANGES ITS PITCH")
    s.add_argument("--remove", action="store_true",
                   help="take the accidental off -- CHANGES ITS PITCH")
    s.add_argument("--show", action="store_true", help="force the glyph to be drawn")
    s.add_argument("--hide", action="store_true", help="stop the glyph being drawn")
    s.add_argument("--color", help="e.g. '#CC4125', or 'none' to clear")
    s.set_defaults(fn=cmd_set_accidental)

    s = sub.add_parser("duplicate", help="Copy a score (its latest version becomes the copy's v001)")
    s.add_argument("score")
    s.add_argument("--name")
    s.set_defaults(fn=cmd_duplicate)

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

    s = sub.add_parser("bulk-import",
                       help="Import a folder of exported scores as pieces and "
                            "arrangements (DRY RUN unless --commit)")
    s.add_argument("folder")
    s.add_argument("--manifest",
                   help='JSON: [{"file": "a.pdf", "piece": "Nature Boy", '
                        '"arrangement": "trio"}]. Overrides the filename rule.')
    s.add_argument("--commit", action="store_true",
                   help="actually write. Without it nothing is created: this "
                        "runs across a whole library and the tree is worth reading first")
    s.set_defaults(fn=cmd_bulk_import)

    s = sub.add_parser("import-book",
                       help="Import a PDF as a BOOK (a collection to take "
                            "arrangements out of, not a piece)")
    s.add_argument("file")
    s.add_argument("--name")
    s.set_defaults(fn=cmd_import_book)

    s = sub.add_parser("book-extract",
                       help="Take pages out of a book as a new arrangement")
    s.add_argument("book")
    s.add_argument("--from-page", dest="from_page", type=int, required=True)
    s.add_argument("--to-page", dest="to_page", type=int, required=True)
    s.add_argument("--name", required=True)
    s.add_argument("--piece", help="file it under this piece (created if missing)")
    s.set_defaults(fn=cmd_book_extract)

    s = sub.add_parser("books", help="List the books in the workspace")
    s.set_defaults(fn=cmd_books)

    s = sub.add_parser("rename-book",
                       help="Rename a book (slug and stored PDF unchanged)")
    s.add_argument("book", help="Book slug")
    s.add_argument("--name", required=True)
    s.set_defaults(fn=cmd_rename_book)

    s = sub.add_parser("piece-create", help="Create a piece (a work that groups arrangements)")
    s.add_argument("name")
    s.set_defaults(fn=cmd_piece_create)

    s = sub.add_parser("piece-assign", help="File an arrangement under a piece (created if missing)")
    s.add_argument("score")
    s.add_argument("--piece", help="Piece name or slug")
    s.add_argument("--unassign", action="store_true", help="Remove the score from its piece")
    s.set_defaults(fn=cmd_piece_assign)

    s = sub.add_parser("piece-rename", help="Rename a piece (slug stays the same)")
    s.add_argument("piece", help="Piece name or slug")
    s.add_argument("--name", required=True)
    s.set_defaults(fn=cmd_piece_rename)

    s = sub.add_parser("set-structure",
                       help="Repeats, voltas and navigation marks (add/remove/move)")
    s.add_argument("score")
    s.add_argument("--kind", required=True,
                   help="repeat-start|repeat-end|repeat-both|volta|segno|coda|fine|"
                        "da-capo[-al-fine|-al-coda]|dal-segno[-al-fine|-al-coda]")
    s.add_argument("--measure", type=int)
    s.add_argument("--to-measure", type=int, dest="to_measure",
                   help="last measure of a volta")
    s.add_argument("--number", type=int, help="volta number (1st, 2nd ending)")
    s.add_argument("--times", type=int, help="play count on a repeat-end")
    s.add_argument("--move-to", type=int, dest="move_to")
    s.add_argument("--remove", action="store_true")
    s.set_defaults(fn=cmd_set_structure)

    s = sub.add_parser("whistle-fingerings",
                       help="Write penny-whistle fingerings under a part")
    s.add_argument("score")
    s.add_argument("--part", required=True)
    s.add_argument("--whistle", default="D", help="whistle key (D, C, E-, F, G, A)")
    s.add_argument("--clear", action="store_true", help="remove fingerings instead")
    s.set_defaults(fn=cmd_whistle_fingerings)

    s = sub.add_parser("guitar-tab",
                       help="Write guitar tablature under a part")
    s.add_argument("score")
    s.add_argument("--part", required=True)
    s.add_argument("--tuning", default="EADGBE",
                   help="EADGBE (standard), DADGAD, DADGBE (drop D)")
    s.add_argument("--capo", type=int, default=0, help="fret the capo sits on")
    s.add_argument("--position", type=int,
                   help="fret the hand starts at; left alone the line settles "
                        "as low on the neck as the music allows")
    s.add_argument("--clear", action="store_true", help="remove the tab instead")
    s.set_defaults(fn=cmd_guitar_tab)

    s = sub.add_parser("chord-diagrams",
                       help="Engrave guitar chord diagrams over a part's chord symbols")
    s.add_argument("score")
    s.add_argument("--part", required=True)
    s.add_argument("--tuning", default="EADGBE",
                   help="EADGBE (standard), DADGAD, DADGBE (drop D)")
    s.add_argument("--clear", action="store_true", help="remove the diagrams instead")
    s.add_argument("--shape", action="append", metavar="CHORD=FRETS",
                   help="pin a chord to a shape of your own, ahead of the "
                        "chart and the search: --shape \"A7=x02020\". Repeatable.")
    s.set_defaults(fn=cmd_chord_diagrams)

    s = sub.add_parser("adjust-element",
                       help="size and position of an added element "
                            "(chord symbols, diagrams, dynamics, text, "
                            "fermatas, articulations)")
    s.add_argument("score")
    s.add_argument("--part", required=True)
    s.add_argument("--kind", default="harm",
                   help="|".join(sorted(ops.ADJUSTABLE_KINDS)))
    s.add_argument("--measure", type=int)
    s.add_argument("--ordinal", type=int, default=0)
    s.add_argument("--scale", type=float,
                   help="size RELATIVE to the engraved default: 1.0 leaves it, "
                        "1.5 is half again")
    s.add_argument("--size", type=float,
                   help="absolute point size, for a caller that already holds "
                        "one; use --scale instead")
    s.add_argument("--offset-x", dest="offset_x", type=float)
    s.add_argument("--offset-y", dest="offset_y", type=float)
    s.add_argument("--all", action="store_true", help="every element of that kind")
    s.add_argument("--reset", action="store_true")
    s.set_defaults(fn=cmd_adjust_element)

    for verb, fn in (("move", cmd_move_element),
                     ("duplicate", cmd_duplicate_element)):
        s = sub.add_parser(
            f"{verb}-element",
            help=f"{verb.capitalize()} an added element to another bar "
                 "(spanners are out of scope)")
        s.add_argument("score")
        s.add_argument("--part", required=True)
        s.add_argument("--kind", required=True,
                       help="|".join(sorted(ops.MOVABLE_KINDS)))
        s.add_argument("--measure", type=int, required=True,
                       help="the bar it is in now")
        s.add_argument("--ordinal", type=int, default=0,
                       help="which one in that bar, in document order")
        s.add_argument("--to-measure", dest="to_measure", type=int,
                       help="the bar it goes to (default: the one it is in)")
        s.add_argument("--to-offset", dest="to_offset", type=float, default=0.0,
                       help="quarter notes from that barline: 0 is the downbeat")
        s.set_defaults(fn=fn)

    s = sub.add_parser("rename-slug",
                       help="Change the slug a score is filed under (moves artifacts)")
    s.add_argument("score")
    s.add_argument("--to", required=True, help="the new slug (normalized like an import)")
    s.set_defaults(fn=cmd_rename_slug)

    s = sub.add_parser("set-metadata",
                       help="Edit a score's metadata (title engraves on the page)")
    s.add_argument("score")
    s.add_argument("--title", help="the arrangement's title, engraved at the top")
    s.add_argument("--composer", help="composer credit ('' clears it)")
    s.add_argument("--arranger", help="arranger credit ('' clears it)")
    s.set_defaults(fn=cmd_set_metadata)

    s = sub.add_parser("repair-titles",
                       help="Re-title arrangements engraving an internal file "
                            "name (lists them; --apply writes a new version each)")
    s.add_argument("--apply", action="store_true",
                   help="write the corrected titles (without it, only lists)")
    s.set_defaults(fn=cmd_repair_titles)

    s = sub.add_parser("set-piece-metadata",
                       help="Edit a PIECE's composer and tags (a scan has no "
                            "notation to credit, so this is where it lives)")
    s.add_argument("piece")
    s.add_argument("--composer", help="composer credit ('' clears it)")
    s.add_argument("--tags", help="comma-separated ('' clears them)")
    s.add_argument("--arranger", help="arranger credit ('' clears it)")
    s.set_defaults(fn=cmd_set_piece_metadata)

    s = sub.add_parser("tags", help="Every tag in use, most-used first")
    s.set_defaults(fn=cmd_tags)

    s = sub.add_parser("rename-score",
                       help="Rename an arrangement (label only; slug and versions unchanged)")
    s.add_argument("score")
    s.add_argument("--name", required=True)
    s.set_defaults(fn=cmd_rename_score)

    s = sub.add_parser("delete-score", help="Delete a score, its versions, and its files (irreversible)")
    s.add_argument("score")
    s.set_defaults(fn=cmd_delete_score)

    s = sub.add_parser("serve", help="Run the local engine API (viewer uploads, exports, chat, iOS app)")
    s.add_argument("--port", type=int, default=8765)
    s.add_argument("--host", default="127.0.0.1",
                   help="Bind address; use 0.0.0.0 to allow the iPad app on your LAN")
    s.set_defaults(fn=cmd_serve)

    s = sub.add_parser("bundle-export",
                       help="An arrangement or setlist as one shareable file "
                            "(AirDrop, Files) -- no account, no network")
    s.add_argument("target", help="arrangement slug, or setlist name")
    s.add_argument("--out", required=True)
    s.add_argument("--full-history", action="store_true",
                   help="every version, not just the one it opens at")
    s.add_argument("--ink", help="annotations directory, to carry markup along")
    s.set_defaults(fn=cmd_bundle_export)

    s = sub.add_parser("bundle-inspect", help="What is inside a bundle. Reads only.")
    s.add_argument("path")
    s.set_defaults(fn=cmd_bundle_inspect)

    s = sub.add_parser("bundle-import", help="Take a bundle in as new arrangements")
    s.add_argument("path")
    s.add_argument("--into-piece", help="file every arrangement under this piece")
    s.add_argument("--ink", help="annotations directory, to restore markup into")
    s.set_defaults(fn=cmd_bundle_import)

    s = sub.add_parser("export", help="Export a version to a file (optionally only some parts)")
    s.add_argument("score")
    s.add_argument("--format", choices=["musicxml", "midi", "pdf"], default="musicxml")
    s.add_argument("--out", required=True)
    s.add_argument("--version")
    s.add_argument("--parts", help="Only include these parts (comma-separated)")
    s.set_defaults(fn=cmd_export)

    s = sub.add_parser("playback",
                       help="Write the score AS PERFORMED to MIDI, with the map "
                            "from its beats back to the engraved bars")
    s.add_argument("score")
    s.add_argument("--out", required=True)
    s.add_argument("--version")
    s.set_defaults(fn=cmd_playback)

    a = p.parse_args()
    try:
        a.fn(a)
    except Exception as e:
        print(json.dumps({"error": f"{type(e).__name__}: {e}"}), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
