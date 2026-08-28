"""Removing an orphaned piece, THROUGH THE BRIDGE the app actually talks to.

`check_pieces.py` already proves the rule in the engine: a piece cannot exist
without an arrangement. It was green the whole time Ali was looking at
"Morrison's Jig -- unknown - 0 arrangements" on his iPad, with a Delete that did
nothing. The reason it could be green and wrong is that it calls Python
functions directly, and the app does not: it goes through `bridge.py`, and the
shipped bridge had NO `delete-piece` op at all. The call raised "unknown op",
the error landed in `lastError`, and nothing happened on screen.

So this walks the same ground one layer out, where the failure actually lived:

  - an empty piece SURVIVES on its own (a piece named for an import that has
    not landed yet must not vanish before its first arrangement -- that rule
    was narrowed deliberately in 0.4.2 and is not a bug)
  - `tidy-pieces` removes it when asked, which is what clears an orphan left by
    an older build
  - `delete-piece` removes it when the user asks, addressed by SLUG, which is
    what the app sends
  - and neither takes anything else with it

Run: engine/.venv/bin/python engine/scripts/check_orphan_piece_bridge.py
"""

import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine"))
sys.path.insert(0, str(ROOT / "ios" / "PythonApp" / "app"))

FAILURES: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {label}")
    else:
        FAILURES.append(f"{label}{': ' + detail if detail else ''}")
        print(f"  FAIL {label}{': ' + detail if detail else ''}")


def main() -> int:
    workspace = tempfile.mkdtemp(prefix="scoranger-orphan-")
    os.environ["SCORANGER_WORKSPACE"] = workspace

    import bridge
    from music21 import note, stream

    def call(op, **args):
        return json.loads(bridge.handle(json.dumps({"op": op, "args": args})))

    def pieces():
        manifest = call("manifest").get("result") or {}
        return {p["slug"]: len(p["arrangements"]) for p in (manifest.get("pieces") or [])}

    def seed(name: str) -> str:
        score = stream.Score()
        part = stream.Part()
        part.partName = "Flute"
        for pitch in ("C4", "D4"):
            part.append(note.Note(pitch, quarterLength=2.0))
        score.append(part)
        path = Path(workspace) / f"{name}.musicxml"
        score.write("musicxml", fp=str(path))
        return str(path)

    print("an empty piece is allowed to exist")
    r = call("create-piece", name="Morrison's Jig")
    check("create-piece works through the bridge", r.get("ok") is True,
          str(r.get("error"))[:200])
    check("it is in the manifest with nothing in it",
          pieces().get("morrison-s-jig") == 0, str(pieces()))

    # It must survive: a piece named for an import that has not arrived yet is
    # exactly what the 0.4.2 narrowing protects.
    call("manifest")
    check("and it survives a manifest rebuild",
          pieces().get("morrison-s-jig") == 0,
          "a piece created for an import must not vanish before it lands")

    print("\ndelete-piece removes it -- addressed by slug, as the app sends it")
    r = call("delete-piece", piece="morrison-s-jig", with_arrangements=True)
    check("the bridge answers delete-piece", r.get("ok") is True,
          f"this is the call that silently did nothing on device: {r.get('error')}")
    check("the orphan is gone", "morrison-s-jig" not in pieces(), str(pieces()))

    print("\ntidy-pieces sweeps ones left behind by an older build")
    # The real piece FIRST: importing files an arrangement, and that path
    # already drops other empty pieces, so orphans created before it would be
    # swept by the import rather than by the sweep under test.
    r = call("import", path=seed("real"), name="Real Tune", piece="Real Piece")
    check("a real piece and arrangement exist", r.get("ok") is True,
          str(r.get("error"))[:200])
    call("create-piece", name="Leftover")
    call("create-piece", name="Also Leftover")
    before = pieces()
    check("two orphans and one real piece are present",
          before.get("leftover") == 0 and before.get("also-leftover") == 0
          and before.get("real-piece") == 1, str(before))

    r = call("tidy-pieces")
    check("the bridge answers tidy-pieces", r.get("ok") is True,
          str(r.get("error"))[:200])
    tidied = (r.get("result") or {}).get("tidied")
    check("it reports what it removed", isinstance(tidied, list) and len(tidied) == 2,
          str(tidied))

    after = pieces()
    check("both orphans are swept", "leftover" not in after and "also-leftover" not in after,
          str(after))
    check("the real piece is untouched", after.get("real-piece") == 1, str(after))

    print("\nand the arrangement inside the real piece is still there")
    manifest = call("manifest").get("result") or {}
    scores = manifest.get("scores") or []
    check("its arrangement survived the sweep", len(scores) == 1, str(len(scores)))

    print("\ndeleting the last arrangement drops its piece on the spot")
    slug = scores[0]["slug"] if scores else None
    if slug:
        r = call("delete-score", score=slug)
        check("delete-score works", r.get("ok") is True, str(r.get("error"))[:200])
        check("the piece went with its only arrangement",
              "real-piece" not in pieces(), str(pieces()))

    print("\ntidying an already-tidy library removes nothing")
    r = call("tidy-pieces")
    check("it is safe to run every launch",
          (r.get("result") or {}).get("tidied") == [], str(r.get("result")))

    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)}")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: an orphaned piece can be swept and can be deleted, through the "
          "bridge the app actually calls -- the layer that was missing the op "
          "while the engine tests stayed green")
    return 0


if __name__ == "__main__":
    sys.exit(main())
