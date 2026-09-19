"""What a parser dropped, put back on the score it dropped it from.

A stage AFTER parsing, with one input and one output: the source text a
reader handed us and the stream music21 made of it, in; the same stream with
the marks music21 discarded attached to the right notes, out. Nothing here
writes notation as text and nothing here edits a file -- the golden rule holds
-- it reads the SOURCE to find out what was said, and then says it again in
music21 objects.

ABC decorations are the first thing to need this and the reason the module
exists. They will not be the last: every importer this engine has loses
something its format can say and MusicXML can hold, and the alternative to a
named stage is a special case inside `workspace.read_notation` for each one.

HOW A MARK FINDS ITS NOTE. By COUNTING, not by guessing. `scan` walks the ABC
and numbers every note event it contains -- a note, a chord, a visible rest --
in the order the file writes them, which is the order music21 emits them. A
decoration is recorded against the number of the event it precedes. After the
parse, event N is `notesAndRests[N]`.

That is only safe while the two counts agree, so `restore` CHECKS them, twice:

  - the whole tune's event count against the stream's, and
  - for every decoration, the note LETTER the ABC wrote against the step of
    the note it is about to be attached to.

Either disagreeing means this module has mis-read some ABC construct, and a
mark hung on the wrong note is worse than a mark reported as lost -- so on a
mismatch nothing is attached to that tune and the count is REPORTED. The
report is the point: a reader whose rolls vanished is owed the number, which
is what `workspace.abc_losses` has always said and this keeps true.

WHY THE TEXT IS STRIPPED FIRST. music21's ABC tokenizer treats a decoration as
part of the note event's string and then throws several of those strings away
(`abcFormat.ABCHandler.tokenize`). For `H` it throws away THE NOTE: `HA2 B2 c2
d2` parses as three notes, and a tune imported with a fermata in it was
quietly missing one. Removing the marks before the parse is what makes the
note survive; re-attaching them afterwards is what makes them survive. The two
halves are one mechanism and neither works alone.
"""

from __future__ import annotations

import re
import tempfile
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Decoration:
    """One mark the ABC wrote, and the note event it was written against."""

    #: index of the tune within the file, in `X:` order
    tune: int
    #: index of the note event within that tune, in the order it is written
    event: int
    #: canonical name -- a key of `DECORATIONS`
    mark: str
    #: the mark exactly as the file spelled it, for a report to quote
    source: str
    #: the ABC note letter it sat on, upper-cased; None on a rest or a chord.
    #: `restore` checks this against the note it is about to attach to.
    step: str | None


#: The four `!...!` decorations music21's own tokenizer acts on. They are
#: SPANNERS -- two anchors -- and music21 already builds the Crescendo and the
#: Diminuendo correctly, so they are left in the text for it to find. This
#: module never touches a spanner: see `ops.SPANNER_KINDS` for why an op in
#: this repo refuses to guess a spanner's far end.
_M21_SPANNER_DECORATIONS = {"!crescendo(!", "!crescendo)!",
                            "!diminuendo(!", "!diminuendo)!"}

#: canonical name -> every way ABC spells it. The shorthand letters are the
#: ABC 2.2 standard's decoration set plus `J` (slide), which abcm2ps defines
#: and thesession.org's transcriptions use. The `!...!` long forms are the
#: standard's, with the aliases real files carry.
#:
#: Spelled this way round because one mark has several spellings and the
#: reverse index is built from it -- two tables would drift.
_SPELLINGS: dict[str, tuple[str, ...]] = {
    "fermata": ("H", "!fermata!", "!H!"),
}

#: what each canonical mark BECOMES: (family, music21 class name).
#: "articulation" hangs off a note's `.articulations`, "expression" off its
#: `.expressions`, "navigation" is inserted into the note's MEASURE because it
#: marks a place in the form rather than a note (see `ops.NAVIGATION_MARKS`),
#: and "dynamic" is inserted at the note's offset.
DECORATIONS: dict[str, tuple[str, str]] = {
    "fermata": ("expression", "Fermata"),
}

#: shorthand/long spelling -> canonical name, built from `_SPELLINGS`.
_BY_SPELLING = {spelling: mark
                for mark, spellings in _SPELLINGS.items()
                for spelling in spellings}

#: the single characters above, for the walker to test membership against
_SHORTHAND = {s for s in _BY_SPELLING if len(s) == 1}

#: A field line: `T: title`, `K: Edor`, `w: lyrics`. Never music.
_FIELD_LINE = re.compile(r"^\s*[A-Za-z]:")

#: `X:` opens a tune. One file may hold many.
_TUNE_START = re.compile(r"^\s*X\s*:")


def _tunes(text: str) -> list[tuple[int, int]]:
    """(start, end) line indices of each `X:` block, in the order written."""
    lines = text.splitlines()
    starts = [i for i, line in enumerate(lines) if _TUNE_START.match(line)]
    if not starts:
        return [(0, len(lines))]
    bounds = []
    for n, start in enumerate(starts):
        end = starts[n + 1] if n + 1 < len(starts) else len(lines)
        bounds.append((start, end))
    return bounds


def scan(text: str) -> tuple[str, list[Decoration], list[str]]:
    """The ABC with its decorations removed, where each one was, and the rest.

    Returns (stripped text, decorations found, spellings left behind). The
    third is every `!...!` this module has no music21 object for; they stay in
    the text (music21 ignores them either way) and are REPORTED, because a
    silent drop is the thing this module exists to end.
    """
    lines = text.splitlines(keepends=True)
    out_lines = list(lines)
    found: list[Decoration] = []
    unknown: list[str] = []

    for tune_index, (start, end) in enumerate(_tunes(text)):
        events = 0
        for row in range(start, end):
            if row >= len(lines):
                break
            line = lines[row]
            if _FIELD_LINE.match(line) or line.lstrip().startswith("%"):
                continue
            stripped, events, marks, left = _scan_line(line, tune_index, events)
            out_lines[row] = stripped
            found.extend(marks)
            unknown.extend(left)
    return "".join(out_lines), found, unknown


def _scan_line(line: str, tune: int, events: int
               ) -> tuple[str, int, list[Decoration], list[str]]:
    """One body line: the same line with decorations cut out, and what they were.

    A character walk rather than a regular expression, because whether a `T`
    is a trill depends on what precedes it -- inside `"..."` it is part of a
    chord symbol, before a `:` it opens a field somebody wrote without
    brackets, and `[K:G]` is not a chord. Each of those is one branch here and
    none of them is expressible as a pattern over the whole line.
    """
    kept: list[str] = []
    pending: list[tuple[str, str]] = []   # (canonical mark, as written)
    found: list[Decoration] = []
    unknown: list[str] = []
    i, n = 0, len(line)

    def attach(step: str | None) -> None:
        nonlocal events
        for mark, source in pending:
            found.append(Decoration(tune, events, mark, source, step))
        pending.clear()
        events += 1

    while i < n:
        c = line[i]

        if c == "%":                      # comment to end of line
            kept.append(line[i:])
            break

        if c == '"':                      # chord symbol or annotation
            close = line.find('"', i + 1)
            close = n if close < 0 else close + 1
            kept.append(line[i:close])
            i = close
            continue

        if c in "!+":                     # long-form decoration
            close = line.find(c, i + 1)
            if close < 0 or "\n" in line[i:close]:
                kept.append(c)            # a lone `!` is an old line break
                i += 1
                continue
            token = line[i:close + 1]
            body = token[1:-1]
            canonical = _BY_SPELLING.get(f"!{body}!")
            if canonical is not None:
                pending.append((canonical, token))
            elif token in _M21_SPANNER_DECORATIONS:
                kept.append(token)        # music21 builds these itself
            else:
                kept.append(token)
                unknown.append(token)
            i = close + 1
            continue

        if c == "[":
            if re.match(r"\[[A-Za-z]:", line[i:]):   # inline field, not a chord
                close = line.find("]", i + 1)
                close = n if close < 0 else close + 1
                kept.append(line[i:close])
                i = close
                continue
            close = line.find("]", i + 1)            # a chord: ONE event
            close = n - 1 if close < 0 else close
            kept.append(line[i:close + 1])
            i = close + 1
            attach(None)
            continue

        if c in _SHORTHAND and not line[i + 1:i + 2] == ":":
            pending.append((_BY_SPELLING[c], c))
            i += 1
            continue

        if c == "z":                      # a rest music21 keeps
            kept.append(c)
            i += 1
            attach(None)
            continue

        if c in "xXZ":                    # rests music21 discards: not events
            kept.append(c)
            i += 1
            continue

        if c.isalpha() and c in "ABCDEFGabcdefg":
            kept.append(c)
            i += 1
            attach(c.upper())
            continue

        kept.append(c)                    # bars, slurs, ties, lengths, spaces
        i += 1

    # a decoration at the end of a line applies to the next line's first note;
    # carrying it would need state across lines, and no real file does it
    return "".join(kept), events, found, unknown


def _restore_one(score, marks: list[Decoration]) -> dict:
    """Attach one tune's decorations to its notes. See the module docstring."""
    from music21 import expressions as m21expressions

    events = list(score.flatten().notesAndRests)
    report = {"carried": 0, "uncarried": 0, "reason": None}
    if not marks:
        return report

    counted = max(m.event for m in marks) + 1
    if counted > len(events):
        report["uncarried"] = len(marks)
        report["reason"] = (
            f"the tune reads as {len(events)} note events and its decorations "
            f"are written against {counted}, so nothing could be placed "
            f"without risking the wrong note")
        return report

    for mark in marks:
        target = events[mark.event]
        if mark.step is not None and getattr(target, "step", None) != mark.step:
            report["uncarried"] += 1
            continue
        family, class_name = DECORATIONS[mark.mark]
        if family == "expression":
            obj = getattr(m21expressions, class_name)()
            if class_name == "Fermata":
                # music21 defaults a Fermata to `inverted`, which MusicXML
                # draws UNDER the note; ABC's `H` is the one above it. The
                # same choice `ops._make_element` makes.
                obj.type = "upright"
            target.expressions.append(obj)
            report["carried"] += 1
        else:
            report["uncarried"] += 1
    return report


def restore(scores: list, marks: list[Decoration]) -> dict:
    """Put every scanned decoration on its note. Returns what it managed."""
    carried = uncarried = 0
    reasons: list[str] = []
    for index, score in enumerate(scores):
        one = _restore_one(score, [m for m in marks if m.tune == index])
        carried += one["carried"]
        uncarried += one["uncarried"]
        if one["reason"]:
            reasons.append(f"tune {index + 1}: {one['reason']}")
    out = {"carried": carried, "uncarried": uncarried}
    if reasons:
        out["reasons"] = reasons
    return out


def read_abc(path) -> tuple[list, dict]:
    """Every tune in an ABC file, with its decorations on it.

    The scan-strip-parse-restore cycle in one call, which is the whole stage:
    `workspace.read_notation` hands it a path and gets back what the file
    said, not what music21 could hold of it.
    """
    from music21 import converter, stream

    source = Path(path)
    text = source.read_text(encoding="utf-8", errors="replace")
    stripped, marks, unknown = scan(text)

    # Parsed from a temp copy under the SAME stem: music21 seeds the movement
    # title with the file name, and `cli.cmd_import` reads that title back out
    # as the arrangement's name when the tune does not name itself.
    with tempfile.TemporaryDirectory(prefix="scoranger-abc-") as tmp:
        copy = Path(tmp) / source.name
        copy.write_text(stripped, encoding="utf-8")
        parsed = converter.parse(str(copy), forceSource=True)
    scores = list(parsed.scores) if isinstance(parsed, stream.Opus) else [parsed]

    report = restore(scores, marks)
    if unknown:
        report["unknown"] = sorted(set(unknown))
    return scores, report
