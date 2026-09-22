#!/usr/bin/env python3
"""What the chat's version history sends a model provider, and what it does not.

`list_versions` is an ordinary tool: a model calls it to see what has already
been done to a score. Its ANSWER leaves the device, to OpenRouter and to
whatever model sits behind it.

The iOS bridge answered it with `workspace.load_meta` whole. A version document
carries `file` (the artifact's filename), `uid`, `parent`, `time`, a full
`parts` snapshot -- and `turn.prompt`, WHICH IS THE FIRST 200 CHARACTERS OF AN
EARLIER USER PROMPT (`workspace.begin_turn`). So one tool call handed the
provider a running transcript of what the user had been asking for, plus the
filenames of their scores, none of which any model needs to reason about
history.

The desktop agent had always projected the same call down to `{id, op, args}`.
Two implementations of one tool, and they disagreed by everything above; the
one on the device Ali's family uses was the wider of the two.

WHAT IS ASSERTED:

  1. ONE implementation. `chat.list_versions` and bridge.py's `versions` op
     both call `workspace.version_history` and neither calls `load_meta`. This
     is the assertion that survives the next field being added to a version
     document -- a test that listed forbidden field names would pass a new one
     silently.
  2. The projection drops what it should, driven by a REAL score with a REAL
     chat turn open, so `turn.prompt` is genuinely present in the document
     being projected. A check run against a document with no turn would prove
     nothing about the field that matters most.
  3. It keeps what the tool is for: id, op and args, on every version.
  4. NO VALUE ANYWHERE in the answer contains the prompt text -- checked by
     searching the serialised JSON for a sentinel, not by listing keys, so a
     prompt reaching the model under a different key is still caught.
  5. `load_meta` itself is UNCHANGED and still returns everything. It is what
     the CLI, the manifest and the app's own UI read; narrowing it would have
     been a data loss dressed as a privacy fix.

Run: engine/.venv/bin/python engine/scripts/check_version_history.py
"""
import json
import os
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine"))

FAILURES: list[str] = []


def check(ok: bool, label: str) -> None:
    print(f"    {'ok  ' if ok else 'FAIL'} {label}")
    if not ok:
        FAILURES.append(label)


def code_of(path: Path) -> str:
    """Source with comment lines dropped: every assertion here is about code."""
    return "\n".join(l for l in path.read_text().splitlines()
                     if not l.lstrip().startswith("#"))


def the_two_surfaces_share_one_implementation() -> None:
    print("\nthe iPad and the desktop answer list_versions with the same code")
    chat = code_of(ROOT / "engine" / "scoranger_engine" / "chat.py")
    bridge = code_of(ROOT / "ios" / "PythonApp" / "app" / "bridge.py")

    chat_fn = chat[chat.index("def list_versions"):]
    chat_fn = chat_fn[:chat_fn.index("\ndef ", 1)]
    check("version_history" in chat_fn,
          "chat.list_versions calls workspace.version_history")
    check("load_meta" not in chat_fn,
          "and does not call load_meta")

    m = re.search(r'if op == "versions":(.*?)\n    if op ==', bridge, re.S)
    check(m is not None, "bridge.py answers the `versions` op")
    if m:
        body = m.group(1)
        check("version_history" in body,
              "the bridge's `versions` op calls workspace.version_history")
        check("load_meta" not in body,
              "and does not call load_meta -- the defect this check exists for")


def the_projection_drops_the_prompt() -> None:
    print("\nand that code sends no prompt text, no filename, no uid")
    from music21 import converter, note, stream

    SENTINEL = "make the viola part sound like a hurdy gurdy in bar 41"

    with tempfile.TemporaryDirectory() as tmp:
        os.environ["SCORANGER_WORKSPACE"] = tmp
        for mod in [m for m in sys.modules if m.startswith("scoranger_engine")]:
            del sys.modules[mod]
        from scoranger_engine import ops, workspace  # noqa: F401

        part = stream.Part(id="Viola")
        part.append([note.Note("C4"), note.Note("E4")])
        score = stream.Score([part])
        slug, _ = workspace.create_score("Projection Jig", score)

        # A REAL turn, so the version really carries turn.prompt. Without this
        # the check passes on a document that never had the field.
        workspace.begin_turn(slug, SENTINEL + " and then some more text that "
                                    "runs past two hundred characters so the "
                                    "excerpt is a genuine excerpt")
        workspace.add_version(slug, score, "transpose", {"interval": "M2"})
        workspace.end_turn()

        raw = workspace.load_meta(slug)
        # The premise, asserted rather than assumed: if load_meta stopped
        # carrying the prompt, everything below would pass for the wrong
        # reason.
        check(any(SENTINEL in json.dumps(v.get("turn", {}))
                  for v in raw["versions"]),
              "load_meta really does carry turn.prompt -- the premise")
        check(any("file" in v for v in raw["versions"]),
              "and really does carry the artifact filename")

        narrow = workspace.version_history(slug)
        blob = json.dumps(narrow)

        # 4: searched by value, not by key.
        check(SENTINEL not in blob,
              "no earlier prompt reaches the model, under any key")
        check(".musicxml" not in blob,
              f"no artifact filename reaches the model; got {blob[:200]}")
        for field in ("uid", "file", "parent", "time", "turn", "parts",
                      "rhythm_warnings"):
            present = [v for v in narrow["versions"] if field in v]
            check(not present, f"no version carries {field!r}")

        # 3: and it still does its job.
        check(narrow["versions"]
              and all(set(v) == {"id", "op", "args"} for v in narrow["versions"]),
              f"every version is exactly id/op/args; got "
              f"{[sorted(v) for v in narrow['versions']]}")
        check(any(v["op"] == "transpose"
                  and v["args"] == {"interval": "M2"}
                  for v in narrow["versions"]),
              "the op and its arguments survive -- that is what history is for")

        # 5: load_meta untouched.
        check(set(raw["versions"][0]) > {"id", "op", "args"},
              "load_meta still returns the whole document for the CLI, the "
              "manifest and the app's own UI")

        # sources, the other half of the answer
        src = stream.Score([stream.Part(id="Fiddle")])
        workspace.add_source(slug, src, "A tab someone posted",
                             "/Users/somebody/Downloads/private-folder/tab.xml")
        narrow = workspace.version_history(slug)
        check(narrow["sources"] and set(narrow["sources"][0]) <= {"id", "name", "parts"},
              f"a source is id/name/parts; got {[sorted(s) for s in narrow['sources']]}")
        check("private-folder" not in json.dumps(narrow),
              "and its origin path -- a folder name off the user's disk -- "
              "does not go to the model")


def main() -> int:
    the_two_surfaces_share_one_implementation()
    the_projection_drops_the_prompt()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: one projection, both surfaces, and no earlier prompt in it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
