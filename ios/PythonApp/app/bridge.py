"""The Swift<->Python boundary: one function, JSON in, JSON out.

Swift calls handle('{"op": ..., "args": {...}}'). The first call must be
"configure" with the workspace path (the app's Documents/workspace). Every
mutating op creates an immutable version, exactly like the desktop CLI.
"""

import json
import os
import sys
import traceback

_ready = False
ops = None
workspace = None


def _ensure_engine():
    global _ready, ops, workspace
    if not _ready:
        from scoranger_engine import ops as _ops
        from scoranger_engine import workspace as _ws
        ops, workspace = _ops, _ws
        _ready = True


def _load(slug, version=None):
    from music21 import converter
    return converter.parse(str(workspace.resolve_path(slug, version)), forceSource=True)


def _mutate(slug, op, args, fn):
    score = _load(slug)
    details = fn(score)
    entry = workspace.add_version(slug, score, op, args)
    return {"new_version": entry["id"], "details": details}


def _part(score, name):
    return ops.find_parts(score, [name])[0]


def _dispatch(op, a):
    if op == "manifest":
        return workspace.rebuild_manifest()
    if op == "selftest":
        # end-to-end: build a score, write+reload MusicXML, transpose,
        # version it in sqlite, then clean up
        from music21 import stream, note, metadata
        s = stream.Score()
        s.metadata = metadata.Metadata(title="Self Test")
        p = stream.Part()
        p.partName = "Test"
        for name in ("C4", "D4", "E4", "F4"):
            p.append(note.Note(name, quarterLength=1.0))
        s.append(p)
        slug, entry = workspace.create_score("Self Test", s, op="selftest", args={})
        reloaded = _load(slug)
        details = ops.transpose(reloaded, "M2", None)
        e2 = workspace.add_version(slug, reloaded, "transpose", {"interval": "M2"})
        pitches = [str(pt) for pt in _load(slug).pitches]
        workspace.delete_score(slug)
        return {"versions": [entry["id"], e2["id"]], "transposed": pitches,
                "details": details}
    if op == "import":
        from music21 import converter
        score = converter.parse(a["path"], forceSource=True)
        name = a.get("name") or os.path.splitext(os.path.basename(a["path"]))[0]
        if score.metadata is not None and not score.metadata.title:
            score.metadata.title = name
        slug, entry = workspace.create_score(name, score, op="import", args={"source": a["path"]})
        piece = None
        if a.get("piece"):
            piece = workspace.assign_score_to_piece(slug, a["piece"])["piece"]
        return {"score": slug, "version": entry["id"], "piece": piece}
    if op == "info":
        return ops.info(_load(a["score"], a.get("version")))
    if op == "versions":
        return workspace.load_meta(a["score"])
    if op == "delete-score":
        workspace.delete_score(a["score"])
        return {"deleted": a["score"]}
    if op == "duplicate":
        src = _load(a["score"])  # latest version becomes the copy's v001
        name = a.get("name") or f"{a['score']} copy"
        slug, entry = workspace.create_score(name, src, op="duplicate",
                                             args={"source": a["score"]})
        # the copy stays filed with its source's piece
        piece = (workspace._repo().get_score(a["score"]) or {}).get("piece")
        if piece:
            workspace.assign_score_to_piece(slug, piece)
        return {"score": slug, "version": entry["id"]}
    if op == "create-piece":
        return workspace.create_piece(a["name"])
    if op == "assign-piece":
        return workspace.assign_score_to_piece(a["score"], a["piece"],
                                               create_if_missing=True)
    if op == "unassign-piece":
        return workspace.assign_score_to_piece(a["score"], None)
    if op == "rename-score":
        return workspace.rename_score(a["score"], a["name"])
    if op == "rename-piece":
        return workspace.rename_piece(a["piece"], a["name"])
    if op == "reorder-piece":
        return workspace.set_piece_order(a["piece"], a["order"])
    if op == "create-setlist":
        return workspace.create_setlist(a["name"])
    if op == "assign-setlist":
        return workspace.add_piece_to_setlist(a["setlist"], a["piece"],
                                              create_if_missing=True)
    if op == "create-arrangement":
        # a minimal valid score: one part, one 4/4 measure with a whole rest
        from music21 import clef, meter, metadata, note, stream
        s = stream.Score()
        name = a.get("name") or "Arrangement"
        s.metadata = metadata.Metadata(title=name)
        p = stream.Part()
        p.partName = "Part 1"
        m = stream.Measure(number=1)
        m.append(clef.TrebleClef())
        m.append(meter.TimeSignature("4/4"))
        m.append(note.Rest(quarterLength=4.0))
        p.append(m)
        s.append(p)
        slug, entry = workspace.create_score(name, s, op="create-arrangement",
                                             args={"piece": a["piece"]})
        workspace.assign_score_to_piece(slug, a["piece"])
        return {"score": slug, "version": entry["id"]}
    if op == "add-source":
        from music21 import converter
        score = converter.parse(a["path"], forceSource=True)
        return workspace.add_source(a["score"], score, a.get("name") or "source", a["path"])
    if op == "analyze":
        return ops.analyze_harmony(_load(a["score"], a.get("version")), a.get("parts"))
    if op == "check-range":
        from music21 import instrument as m21instrument
        score = _load(a["score"])
        p = _part(score, a["part"])
        cls = (type(m21instrument.fromString(a["instrument"])).__name__ if a.get("instrument")
               else type(p.getInstrument(returnDefault=False)).__name__)
        if cls not in ops.RANGES:
            raise ValueError(f"No range data for '{cls}'. Known: {sorted(ops.RANGES)}")
        return {"part": ops.part_label(p), "instrument": cls,
                "violations": ops.range_violations(p, cls)}
    if op == "begin-turn":
        return workspace.begin_turn(a["score"], a.get("prompt") or "")
    if op == "end-turn":
        return workspace.end_turn()
    if op == "version-file":
        return {"path": str(workspace.resolve_path(a["score"], a.get("version")))}
    if op == "source-file":
        return {"path": str(workspace.source_path(a["score"], a["source"]))}

    s = a["score"]
    if op == "keep-parts":
        return _mutate(s, op, a, lambda sc: {"removed": ops.keep_parts(sc, a["parts"])})
    if op == "remove-parts":
        return _mutate(s, op, a, lambda sc: {"removed": ops.remove_parts(sc, a["parts"])})
    if op == "transpose":
        return _mutate(s, op, a, lambda sc: ops.transpose(
            sc, str(a["interval"]), a.get("parts"),
            a.get("from_measure"), a.get("to_measure")))
    if op == "respell":
        return _mutate(s, op, a, lambda sc: ops.respell(
            sc, a.get("prefer", "flats"), a.get("parts"),
            a.get("from_measure"), a.get("to_measure")))
    if op == "change-clef":
        return _mutate(s, op, a, lambda sc: ops.change_clef(_part(sc, a["part"]), a["clef"], a.get("from_measure", 1)))
    if op == "change-instrument":
        return _mutate(s, op, a, lambda sc: ops.change_instrument(_part(sc, a["part"]), a["to"]))
    if op == "rename-part":
        return _mutate(s, op, a, lambda sc: ops.rename_part(_part(sc, a["part"]), a["name"], a.get("abbreviation")))
    if op == "octave-shift":
        return _mutate(s, op, a, lambda sc: ops.octave_shift(sc, a["part"], a["octaves"], a["from_measure"], a["to_measure"]))
    if op == "merge-parts":
        return _mutate(s, op, a, lambda sc: ops.merge_parts(sc, a["parts"], a["name"], a.get("clef", "treble")))
    if op == "split-bass":
        return _mutate(s, op, a, lambda sc: ops.split_bass(sc, a["part"], a["bass_name"], a["chords_name"], a.get("instrument")))
    if op == "absorb-part":
        return _mutate(s, op, a, lambda sc: ops.absorb_part(sc, a["source"], a["target"], a.get("rules")))
    if op == "flatten-voices":
        return _mutate(s, op, a, lambda sc: ops.flatten_voices(sc, a["part"]))
    if op == "consolidate-ties":
        return _mutate(s, op, a, lambda sc: ops.consolidate_ties(sc, a["parts"]))
    if op == "limit-part":
        return _mutate(s, op, a, lambda sc: ops.limit_part(sc, a["part"], a.get("max_pitch"), a.get("monophonic", False)))
    if op == "simplify-repeats":
        return _mutate(s, op, a, lambda sc: ops.simplify_repeats(sc, a["part"]))
    if op == "set-chords":
        return _mutate(s, op, a, lambda sc: ops.set_chord_symbols(sc, a["part"], a["chords"]))
    if op == "chart-style":
        return _mutate(s, op, a, lambda sc: ops.chart_style(sc, a["part"]))
    if op == "pull-part":
        def fn(sc):
            from music21 import converter
            ref = a["from"]
            if ref.startswith("src:"):
                path = workspace.source_path(s, ref[4:])
            elif ref.startswith("arr:"):
                # sibling arrangement of the same piece — latest version
                path = workspace.resolve_path(ref[4:])
            else:
                path = workspace.resolve_path(s, ref)
            src_score = converter.parse(str(path), forceSource=True)
            rng = None
            if a.get("measures"):
                lo, hi = str(a["measures"]).split("-")
                rng = (int(lo), int(hi))
            return ops.pull_part(sc, src_score, a["part"], a.get("as"), a.get("replace"), rng)
        return _mutate(s, op, a, fn)
    raise ValueError(f"unknown op '{op}'")


def handle(request):
    try:
        req = json.loads(request)
        op = req.get("op")
        args = req.get("args") or {}
        if op == "configure":
            os.environ["SCORANGER_WORKSPACE"] = args["workspace"]
            _ensure_engine()
            import music21
            return json.dumps({"ok": True, "python": sys.version.split()[0],
                               "music21": music21.__version__})
        _ensure_engine()
        return json.dumps({"ok": True, "result": _dispatch(op, args)})
    except Exception as e:
        return json.dumps({"ok": False, "error": f"{type(e).__name__}: {e}",
                           "trace": traceback.format_exc()[-1200:]})
