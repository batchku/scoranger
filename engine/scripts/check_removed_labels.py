"""Labels Ali has had removed stay removed.

Some of these have come back. "Pencil: select" sat next to the version number
in the score's top bar, did nothing, and was taken off the bar in 0.6.10 after
he asked -- and he had to ask again two builds later, because taking a chip out
of one bar is not the same as taking a label out of the app. It was still in
the performance strip, still spoken in the Selection & chat screen, and still a
property on ScoreMode for anything new to reach for.

So the removal is asserted where it can be seen from: the SOURCE. A UI test can
only look at the screen it is on, and this label's whole problem was appearing
on screens nobody thought to check.

Comments are exempt. The history of a removal is worth keeping next to the code
that no longer does it -- that is what stopped the chip's yield order being
reintroduced by accident -- and a comment cannot appear on a page.

Run: engine/.venv/bin/python engine/scripts/check_removed_labels.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = [ROOT / "ios" / "Scoranger"]

# what must not be in a user-visible string, and who asked for it gone
REMOVED = [
    ("Pencil: ", "the mode label beside the version number (0.6.10, and again in 0.6.18)"),
]

FAILURES: list[str] = []


def note(label: str, ok: bool) -> None:
    print(("  ok   " if ok else "  FAIL ") + label)
    if not ok:
        FAILURES.append(label)


def code_lines(path: Path):
    """Lines with the comments taken out, so history is exempt.

    Crude on purpose: a `//` anywhere but inside a string literal starts a
    comment, and the only thing that matters here is whether the needle is left
    in code. A block comment is handled by tracking depth.
    """
    depth = 0
    for number, raw in enumerate(path.read_text().splitlines(), start=1):
        line = raw
        if depth:
            end = line.find("*/")
            if end == -1:
                continue
            line, depth = line[end + 2:], depth - 1
        start = line.find("/*")
        if start != -1:
            line, depth = line[:start], depth + 1
        marker = line.find("///")
        if marker == -1:
            marker = line.find("//")
        if marker != -1:
            quotes = line[:marker].count('"') - line[:marker].count('\\"')
            if quotes % 2 == 0:      # not inside a string literal
                line = line[:marker]
        yield number, line


# Only inside a string LITERAL. `isPencil: Bool` is an argument label and a
# dozen of them are load-bearing; what must not exist is text that can be
# engraved on a screen.
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


def literals(line: str):
    return LITERAL.findall(line)


for needle, who in REMOVED:
    hits = []
    for root in SOURCES:
        for path in sorted(root.rglob("*.swift")):
            for number, line in code_lines(path):
                for text in literals(line):
                    if needle in text:
                        hits.append(f"{path.relative_to(ROOT)}:{number}: \"{text[:70]}\"")
    note(f'"{needle}" is gone from every user-visible string -- {who}'
         + ("" if not hits else "\n         " + "\n         ".join(hits)),
         not hits)

if FAILURES:
    print(f"\nFAIL: {len(FAILURES)} label(s) came back")
    sys.exit(1)
print("\nOK: the labels Ali had removed are still removed")
