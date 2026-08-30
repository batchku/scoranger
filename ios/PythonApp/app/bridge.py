"""The Swift<->Python boundary: one function, JSON in, JSON out.

Swift calls handle('{"op": ..., "args": {...}}'). The first call must be
"configure" with the workspace path (the app's Documents/workspace). Every
mutating op creates an immutable version, exactly like the desktop CLI.
"""

import json
import os
import shutil
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
    # resolve_notation_path: a PDF arrangement is refused here with a sentence
    # a reader can act on, rather than a music21 parse error
    return converter.parse(str(workspace.resolve_notation_path(slug, version)),
                           forceSource=True)


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
    if op == "add-version-from-file":
        # OMR on demand: the transcription becomes a NEW VERSION of the same
        # arrangement, not a new arrangement. The scan stays as v001, so the
        # reader can flip between the page they know and the transcription of
        # it -- which is exactly what checking OMR output requires.
        from music21 import converter

        score = converter.parse(a["path"], forceSource=True)
        entry = workspace.add_version(s_slug := a["score"], score,
                                      a.get("op") or "omr", a.get("args") or {})
        out = {"score": s_slug, "version": entry["id"]}
        if entry.get("rhythm_warnings"):
            out["rhythm_warnings"] = entry["rhythm_warnings"]
        return out
    if op == "import-book":
        # A BOOK, not a piece and not an arrangement: a collection that
        # arrangements are taken out of.
        name = a.get("name") or os.path.splitext(os.path.basename(a["path"]))[0]
        slug, doc = workspace.create_book(name, a["path"])
        return {"book": slug, "name": doc["name"], "pages": doc["pages"]}
    if op == "book-extract":
        slug, entry = workspace.extract_from_book(
            a["book"], int(a["from_page"]), int(a["to_page"]),
            a["name"], a.get("piece"))
        return {"score": slug, "version": entry["id"], "piece": a.get("piece")}
    if op == "delete-book":
        workspace.delete_book(a["book"])
        return {"deleted": a["book"]}
    if op == "bulk-import":
        # A whole exported library at once: one folder per piece, its files the
        # arrangements. Plans FIRST and writes only when asked -- this runs
        # across an entire library and the tree is worth reading before it
        # exists.
        from scoranger_engine import bulk

        folder = a["folder"]
        names = []
        for base, _dirs, filenames in os.walk(folder):
            for fn in filenames:
                rel = os.path.relpath(os.path.join(base, fn), folder)
                if not fn.startswith("."):
                    names.append(rel)
        plan = bulk.plan(sorted(names), manifest=a.get("manifest"))
        # Pieces the reader deselected on the plan screen. Dropped from what is
        # WRITTEN, never from what is SHOWN: the plan still lists them, so the
        # numbers a reader approved are the numbers they saw.
        plan = bulk.without(plan, a.get("exclude"))
        if a.get("commit"):
            return {"plan": plan,
                    "result": bulk.run(plan, dry_run=False, root=folder)}
        return {"plan": plan, "result": bulk.run(plan, dry_run=True)}
    if op == "import-pdf":
        # The artifact IS the file: nothing parses it, nothing re-encodes it.
        # A scan reads and takes markup straight away; OMR is a later, explicit
        # step that turns it into an editable arrangement.
        name = a.get("name") or os.path.splitext(os.path.basename(a["path"]))[0]
        slug, entry = workspace.create_pdf_score(name, a["path"], op="import-pdf",
                                                 args={"source": a["path"]})
        piece = None
        if a.get("piece"):
            piece = workspace.assign_score_to_piece(slug, a["piece"])["piece"]
        return {"score": slug, "version": entry["id"], "piece": piece, "kind": "pdf"}
    if op == "import":
        from music21 import converter
        score = converter.parse(a["path"], forceSource=True)
        name = a.get("name") or os.path.splitext(os.path.basename(a["path"]))[0]
        # music21 seeds the movement title with the file name, extension and
        # all, and that is what engraves; normalize before the first version
        stem = os.path.splitext(os.path.basename(a["path"]))[0]
        name = ops.clean_imported_metadata(score, name, source_stem=stem)["title"]
        slug, entry = workspace.create_score(name, score, op="import", args={"source": a["path"]})
        piece = None
        if a.get("piece"):
            piece = workspace.assign_score_to_piece(slug, a["piece"])["piece"]
        # Odd bars in an imported score are reported, never fatal. OMR output is
        # imperfect by nature and the user brings the score in so they can fix
        # it; refusing the import left them unable to open their own music.
        out = {"score": slug, "version": entry["id"], "piece": piece}
        if entry.get("rhythm_warnings"):
            out["rhythm_warnings"] = entry["rhythm_warnings"]
        return out
    if op == "info":
        return ops.info(_load(a["score"], a.get("version")))
    if op == "export":
        # Three formats, three sources -- and only two of them are ours.
        #
        # A version artifact IS MusicXML, so exporting one resolves a path
        # rather than re-serialising: writing it back through music21 would
        # risk changing bytes the user never asked to change. MIDI is a real
        # conversion and goes through music21. PDF is refused here on purpose:
        # `render.py` is not vendored into the app, the on-device engraver is
        # Swift, and chord adjustments and whistle fingerings are applied in
        # THAT pass -- so a PDF built here would not match the page on screen.
        fmt = (a.get("format") or "musicxml").lower()
        slug = a["score"]
        version = a.get("version")
        parts = [p.strip() for p in str(a.get("parts") or "").split(",") if p.strip()]
        stem = f"{slug}-{version}" if version else slug

        if fmt == "pdf":
            raise ValueError(
                "PDF is rendered on device by the Swift renderer, not the "
                "bridge: engraving carries chord adjustments and whistle "
                "fingerings that only that pass applies.")
        if fmt not in ("musicxml", "midi"):
            raise ValueError(f"unknown export format '{fmt}'. "
                             "Use musicxml, midi, or ask Swift for pdf.")

        out_dir = workspace.score_dir(slug).parent / "exports"
        out_dir.mkdir(parents=True, exist_ok=True)

        if fmt == "musicxml" and not parts:
            src = workspace.resolve_path(slug, version)
            dest = out_dir / f"{stem}.musicxml"
            shutil.copyfile(src, dest)
            return {"path": str(dest), "filename": dest.name, "format": fmt}

        score = _load(slug, version)
        if parts:
            ops.keep_parts(score, parts)
            stem = f"{stem}-{'-'.join(p.lower().replace(' ', '-') for p in parts)}"
        if fmt == "musicxml":
            dest = out_dir / f"{stem}.musicxml"
            score.write("musicxml", fp=str(dest))
        else:
            dest = out_dir / f"{stem}.mid"
            score.write("midi", fp=str(dest))
        return {"path": str(dest), "filename": dest.name, "format": fmt}

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
    if op == "restore-score":
        return {"restored": workspace.restore_score(a["score"])["slug"]}
    if op == "sweep":
        return {"swept": workspace.sweep()}
    if op == "tidy-pieces":
        return {"tidied": workspace.tidy_pieces()}
    if op == "delete-piece":
        workspace.delete_piece(a["piece"], with_arrangements=bool(a.get("with_arrangements")))
        return {"deleted": a["piece"]}
    if op == "create-piece":
        return workspace.create_piece(a["name"])
    if op == "assign-piece":
        return workspace.assign_score_to_piece(a["score"], a["piece"],
                                               create_if_missing=True)
    if op == "unassign-piece":
        return workspace.assign_score_to_piece(a["score"], None)
    if op == "rename-score":
        return workspace.rename_score(a["score"], a["name"])
    if op == "set-structure":
        score = _load(a["score"], None)
        details = ops.set_structure(score, a["kind"], measure=a.get("measure"),
                                    to_measure=a.get("to_measure"),
                                    number=a.get("number"), times=a.get("times"),
                                    remove=bool(a.get("remove")),
                                    move_to=a.get("move_to"))
        entry = workspace.add_version(a["score"], score, "set-structure",
                                      {"kind": a["kind"], "measure": a.get("measure")})
        return {"version": entry["id"], "details": details}
    if op == "adjust-element":
        score = _load(a["score"], None)
        details = ops.adjust_element(
            score, a["part"], kind=a.get("kind") or "harm",
            measure=a.get("measure"), ordinal=int(a.get("ordinal") or 0),
            size=a.get("size"), offset_x=a.get("offset_x"), offset_y=a.get("offset_y"),
            reset=bool(a.get("reset")), all_elements=bool(a.get("all")))
        entry = workspace.add_version(a["score"], score, "adjust-element",
                                      {"part": a["part"], "kind": a.get("kind") or "harm",
                                       "measure": a.get("measure")})
        return {"version": entry["id"], "details": details}
    if op == "whistle-fingerings":
        score = _load(a["score"], None)
        part = _part(score, a["part"])
        details = ops.whistle_fingerings(score, part, a.get("whistle") or "D",
                                         clear=bool(a.get("clear")))
        entry = workspace.add_version(a["score"], score, "whistle-fingerings",
                                      {"part": a["part"], "whistle": a.get("whistle") or "D"})
        return {"version": entry["id"], "details": details}
    if op == "rename-slug":
        return workspace.rename_slug(a["score"], a["to"])
    if op == "set-metadata":
        return workspace.set_score_metadata(a["score"], title=a.get("title"),
                                            composer=a.get("composer"),
                                            arranger=a.get("arranger"))
    if op == "rename-piece":
        return workspace.rename_piece(a["piece"], a["name"])
    if op == "reorder-piece":
        return workspace.set_piece_order(a["piece"], a["order"])
    if op == "reorder-setlist":
        return workspace.set_setlist_order(a["setlist"], a["order"])
    if op == "create-setlist":
        return workspace.create_setlist(a["name"])
    if op == "assign-setlist":
        return workspace.add_score_to_setlist(a["setlist"], a["score"],
                                              create_if_missing=True)
    if op == "unassign-setlist":
        return workspace.remove_score_from_setlist(a["setlist"], a["score"])
    if op == "rename-setlist":
        return workspace.rename_setlist(a["setlist"], a["name"])
    if op == "delete-setlist":
        return workspace.delete_setlist(a["setlist"])
    if op == "debug-orphan-arrangement":
        # TEST FIXTURE ONLY, and the only way to produce this shape any more:
        # create_score now rolls the row back if the version does not land, so
        # an arrangement with no versions cannot be made through the normal
        # path. The app calls this solely under -seedBrokenArrangement, to
        # prove that such an arrangement explains itself rather than spinning.
        slug = a.get("slug") or "broken-arrangement"
        workspace._repo().set_score(slug, {
            "id": slug, "slug": slug, "name": a.get("name") or "Morrison's jig",
            "title": a.get("name") or "Morrison's jig", "composer": None,
            "arranger": None, "created": workspace._now(), "latest": None,
        })
        workspace.rebuild_manifest()
        return {"score": slug, "versions": 0}
    if op == "create-arrangement":
        # a minimal valid score: one part, one 4/4 measure with a whole rest
        from music21 import clef, meter, metadata, note, stream
        s = stream.Score()
        name = a.get("name") or "Arrangement"
        s.metadata = metadata.Metadata(title=name, movementName=name)
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
    if op == "transpose-elements":
        return _mutate(s, op, a, lambda sc: ops.transpose_elements(
            sc, str(a["interval"]), list(a["elements"])))
    if op == "respell":
        return _mutate(s, op, a, lambda sc: ops.respell(
            sc, a.get("prefer", "flats"), a.get("parts"),
            a.get("from_measure"), a.get("to_measure")))
    if op == "set-rehearsal":
        return _mutate(s, op, a, lambda sc: ops.set_rehearsal(
            sc, measure=a.get("measure"), mark=a.get("mark"),
            remove=bool(a.get("remove")), move_to=a.get("move_to"),
            reletter=bool(a.get("reletter"))))
    if op == "clean-accidentals":
        return _mutate(s, op, a, lambda sc: ops.normalize_accidentals(sc, a.get("parts")))
    if op == "set-accidental":
        return _mutate(s, op, a, lambda sc: ops.set_accidental(
            sc, list(a["elements"]), show=a.get("show"), add=a.get("add"),
            remove=bool(a.get("remove")), color=a.get("color")))
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
