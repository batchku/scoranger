#!/usr/bin/env python3
"""Does this language data carry the recogniser Audiveris actually uses?

Audiveris 5.11 initialises Tesseract in LEGACY mode. A `.traineddata` file is
a container of numbered components, and the legacy recogniser needs three of
them: inttemp, pffmtable and normproto. The Debian and Ubuntu language
packages are built from tessdata_fast, which holds the LSTM model alone -- so
against those files Audiveris logs "Could not initialize TessBaseAPI
languages: eng in legacy mode", reads no text for the whole run, and every
lyric, chord symbol, title and part name on the page is lost.

Run at image build time (see Dockerfile) so a wrong file fails the build
rather than somebody's scan. Usage: verify_tessdata.py <file> [<file>...]
"""
import struct
import sys
from pathlib import Path

#: component index -> name, for the three the legacy recogniser needs
LEGACY_COMPONENTS = {3: "inttemp", 4: "pffmtable", 5: "normproto"}


def missing_legacy_components(path) -> list[str]:
    """Which legacy components this traineddata file lacks (empty = fine)."""
    data = Path(path).read_bytes()
    count = struct.unpack("<i", data[:4])[0]
    offsets = struct.unpack(f"<{count}q", data[4:4 + 8 * count])
    return [name for index, name in sorted(LEGACY_COMPONENTS.items())
            if index >= len(offsets) or offsets[index] == -1]


def main(paths: list[str]) -> int:
    if not paths:
        print("usage: verify_tessdata.py <traineddata> [...]", file=sys.stderr)
        return 2
    bad = 0
    for path in paths:
        missing = missing_legacy_components(path)
        if missing:
            bad += 1
            print(f"{path}: NO legacy components ({', '.join(missing)}) -- "
                  "Audiveris runs Tesseract in legacy mode and would read no "
                  "text at all from this file", file=sys.stderr)
        else:
            print(f"{path}: legacy components present")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
