#!/usr/bin/env python3
"""A scan comes back with the words and the chord symbols on it.

Two things have to be true for that, and neither is visible in the exported
file when it stops being true -- the score simply arrives with no text on it,
which reads like a bad scan rather than a broken deployment. So both are
asserted here.

  1. **The conversion carries its processing switches.** `lyrics` is the gate
     on lyrics: forced off, a 32-bar lead sheet exported 0 syllables instead
     of 124 and the words came back as 8 dynamics, 23 articulations and 12
     fermatas that are not on the page. It defaults on today, which is exactly
     why it is stated: a default is somebody else's decision to change.
  2. **The image's language data can drive Tesseract's LEGACY recogniser**,
     because that is the one Audiveris 5.11 asks for. The Debian/Ubuntu
     `tesseract-ocr-eng` package is built from tessdata_fast and has no legacy
     components, and with it Audiveris reads NO text at all: no lyrics, no
     chord symbols, no title, no part names. That was the real fault behind
     "OMR loses chord symbols and lyrics"; the switches were never it.

Both checks read the shipped files rather than a copy of their contents, so
an edit that drops a switch or reverts to the apt language data fails here.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "omr-service"))

FAILURES: list[str] = []


def check(ok: bool, label: str) -> None:
    print(f"    {'ok  ' if ok else 'FAIL'} {label}")
    if not ok:
        FAILURES.append(label)


def the_conversion_command_carries_the_switches() -> None:
    print("\nthe Audiveris command line states the switches it depends on")
    import server

    argv = server.audiveris_command("/out", "/in.pdf")
    for switch in ("lyrics", "chordNames"):
        option = f"org.audiveris.omr.sheet.ProcessingSwitches.{switch}=true"
        pairs = [(argv[i], argv[i + 1]) for i in range(len(argv) - 1)]
        check(("-option", option) in pairs,
              f"-option {option} is on the command line")

    # The shape around them matters as much: Audiveris reads -output as the
    # directory and the trailing argument as the input.
    check(argv[0] == server.AUDIVERIS and argv[1:3] == ["-batch", "-export"],
          "still a batch export")
    check(argv[-1] == "/in.pdf" and argv[-3:-1] == ["-output", "/out"],
          f"the PDF is still the last argument, after -output; got {argv[-4:]}")


def the_service_runs_that_command_and_not_another() -> None:
    """Assert against the source, because a second argv would pass the test above.

    The failure this catches is not a wrong command: it is the command being
    rebuilt inline next to the one with the switches on it, which is how the
    switches stop being passed while every check still says they are set.
    """
    print("\nthe worker launches exactly that command")
    source = (ROOT / "omr-service" / "server.py").read_text()
    body = source[source.index("def run_job"):source.index("class Handler")]
    check("audiveris_command(out_dir, pdf_path)" in body,
          "run_job launches audiveris_command(...)")
    popen_args = re.findall(r"subprocess\.Popen\(\s*(.+)", source)
    check(all("audiveris_command" in a for a in popen_args),
          f"every Popen goes through it; got {popen_args}")
    check(source.count("AUDIVERIS,") == 1,
          "the binary is named in one place -- audiveris_command")


def the_image_installs_language_data_the_legacy_recogniser_can_use() -> None:
    print("\nthe image's OCR data carries the legacy recogniser's components")
    import verify_tessdata

    dockerfile = (ROOT / "omr-service" / "Dockerfile").read_text()
    check("tesseract-ocr/tessdata/raw/${TESSDATA_REF}" in dockerfile,
          "language data comes from the tessdata repository, pinned by tag")
    check("sha256sum -c" in dockerfile,
          "and is checked against a digest, not trusted from the network")
    check("verify_tessdata.py" in dockerfile,
          "and the build fails if the file cannot drive the legacy recogniser")
    check(re.search(r"ARG TESSDATA_REF=\d+\.\d+\.\d+", dockerfile) is not None,
          "the pin is a version, not a moving branch")
    # apt's language packages are the ones that cannot work. eng and fra are
    # still installed -- tesseract-ocr depends on eng anyway, and the files are
    # overwritten straight after -- but nothing may rely on them as they are.
    check("tesseract-ocr-deu" not in dockerfile
          and "tesseract-ocr-ita" not in dockerfile,
          "no language is installed that Audiveris could not read")

    # And the verifier itself is honest: it passes a real legacy file and
    # fails a real LSTM-only one, so it cannot silently agree with everything.
    made_up = Path("/nonexistent/eng.traineddata")
    try:
        verify_tessdata.missing_legacy_components(made_up)
        check(False, "the verifier invented an answer for a missing file")
    except OSError:
        check(True, "the verifier reads the file rather than assuming it")
    lstm_only = _lstm_only_traineddata()
    check(verify_tessdata.missing_legacy_components(lstm_only)
          == ["inttemp", "pffmtable", "normproto"],
          "an LSTM-only file is named as missing all three components")
    legacy = _legacy_traineddata()
    check(verify_tessdata.missing_legacy_components(legacy) == [],
          "a file carrying them passes")


def _traineddata(present: set[int]) -> Path:
    """A minimal traineddata header: a count, then one offset per component.

    Synthetic on purpose -- the real files are 4MB and 23MB, and what is being
    tested is the reading of the component table, which is entirely in the
    header. -1 is how tesseract marks a component that is not in the file.
    """
    import struct
    import tempfile

    count = 24
    offsets = [(1024 if i in present else -1) for i in range(count)]
    blob = struct.pack("<i", count) + struct.pack(f"<{count}q", *offsets)
    path = Path(tempfile.mkstemp(suffix=".traineddata")[1])
    path.write_bytes(blob)
    return path


def _lstm_only_traineddata() -> Path:
    return _traineddata({17, 18, 19, 20, 21, 22, 23})


def _legacy_traineddata() -> Path:
    return _traineddata({1, 2, 3, 4, 5, 17, 21, 22, 23})


def main() -> int:
    the_conversion_command_carries_the_switches()
    the_service_runs_that_command_and_not_another()
    the_image_installs_language_data_the_legacy_recogniser_can_use()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: the scan is converted with the switches on, by a recogniser "
          "that can read")
    return 0


if __name__ == "__main__":
    sys.exit(main())
