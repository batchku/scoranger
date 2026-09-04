"""The sound the app plays with has to be IN the app.

`PlaybackSound.bank` used to be an absolute path into macOS:

    /System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls

There is no `System/Library/Components` in the iOS SDK and none in the
simulator runtime's root. It resolved in the simulator only because a simulator
process falls through to the HOST Mac's filesystem, where the file really does
live -- so every audio test passed, on real timbres, while on Ali's iPad
`loadSoundBankInstrument` threw, `AVAudioUnitSampler` fell back to its own
built-in tone, and every part played the same near-sine deaf to every program
change. iOS ships no General MIDI bank an app may load and Apple's is not
redistributable, so the app now carries GeneralUser GS (ios/scripts/fetch_soundfont.sh).

That makes the bank a gitignored build input, like Python.xcframework and the
vendored engine -- and a missing gitignored build input is the failure this
repo has now had four times: the feature works everywhere it is tested and is
simply absent on the device, with nothing saying so.

So five things are asserted here, on the host, before anything is built:

  - the file is there
  - its sha256 is the one fetch_soundfont.sh pins (a truncated download is a
    file that exists)
  - its license travels with it, because somebody else's work ships inside
    this binary
  - project.yml puts it in the app bundle AND in the test bundle -- the test
    bundle has no host app, so a bank wired into the app alone leaves every
    offline render measuring the sampler's fallback tone
  - PlaybackSound resolves it out of a bundle rather than an absolute path,
    which is the mistake itself

and the file's own preset table is read, so the catalogue in GeneralMIDI.swift
is checked against the bank that ships rather than against a specification the
bank might not honour.

Run: engine/.venv/bin/python engine/scripts/check_vendored_soundfont.py
"""

import hashlib
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IOS = ROOT / "ios"
FETCH = IOS / "scripts" / "fetch_soundfont.sh"
BANK = IOS / "Vendor" / "SoundFonts" / "GeneralUser-GS.sf2"
LICENSE = IOS / "Vendor" / "SoundFonts" / "LICENSE.txt"
PROJECT = IOS / "project.yml"
SOUND = IOS / "Scoranger" / "ScoreModel" / "PlaybackSound.swift"
GENERAL_MIDI = IOS / "Scoranger" / "ScoreModel" / "GeneralMIDI.swift"

# SF2 addresses its drum kits as bank 128; AUSampler's percussion bank MSB
# (0x78 = 120) is the GS alias for the same thing, and GeneralUser GS carries
# both. Either is a kit bank; neither is melodic.
MELODIC_BANK = 0
PERCUSSION_BANKS = (128, 120)


def presets(path: Path) -> dict[int, dict[int, str]]:
    """{bank: {program: name}}, read out of the file's own `phdr` chunk."""
    data = path.read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"sfbk":
        raise ValueError("not a SoundFont 2 file")
    # find LIST 'pdta'
    i, start, end = 12, None, None
    while i < len(data) - 8:
        chunk, size = data[i:i + 4], struct.unpack("<I", data[i + 4:i + 8])[0]
        if chunk == b"LIST" and data[i + 8:i + 12] == b"pdta":
            start, end = i + 12, i + 8 + size
            break
        i += 8 + size + (size & 1)
    if start is None:
        raise ValueError("no pdta list")

    banks: dict[int, dict[int, str]] = {}
    i = start
    while i < end - 8:
        chunk, size = data[i:i + 4], struct.unpack("<I", data[i + 4:i + 8])[0]
        if chunk == b"phdr":
            # 38-byte records: name[20], preset, bank, bagNdx, library, genre,
            # morphology. The last is the terminal "EOP" sentinel.
            for offset in range(i + 8, i + 8 + size, 38):
                record = data[offset:offset + 38]
                if len(record) < 38:
                    break
                name = record[:20].split(b"\0")[0].decode("latin-1").strip()
                program, bank = struct.unpack("<HH", record[20:24])
                if name != "EOP":
                    banks.setdefault(bank, {})[program] = name
            return banks
        i += 8 + size + (size & 1)
    raise ValueError("no phdr chunk")


def swift_kit_programs(source: str) -> list[int]:
    """The programs GeneralMIDI.kits offers, read out of the Swift."""
    block = re.search(r"static let kits: \[Instrument\] = \[(.*?)\n    \]",
                      source, re.S)
    if not block:
        return []
    return [int(n) for n in re.findall(r"^\s*\((\d+),", block.group(1), re.M)]


def main() -> int:
    problems: list[str] = []
    notes: list[str] = []

    if not FETCH.exists():
        print(f"  FAIL no fetch script at {FETCH.relative_to(ROOT)}")
        return 1
    script = FETCH.read_text()
    pinned = re.search(r'^SHA256="([0-9a-f]{64})"', script, re.M)
    if not pinned:
        print("  FAIL fetch_soundfont.sh pins no SHA256 to check against")
        return 1
    expected = pinned.group(1)

    # ---------------------------------------------------------- the file
    if not BANK.exists():
        print(f"  FAIL no sound bank at {BANK.relative_to(ROOT)}")
        print("\n  run: ios/scripts/fetch_soundfont.sh")
        return 1
    got = hashlib.sha256(BANK.read_bytes()).hexdigest()
    if got != expected:
        problems.append(f"{BANK.name} is not the pinned file "
                        f"(expected {expected[:12]}, got {got[:12]})")
    else:
        size = BANK.stat().st_size
        notes.append(f"{BANK.name}: {size / 1e6:.1f} MB, digest {got[:12]}")

    if not LICENSE.exists():
        problems.append("LICENSE.txt is not beside the bank -- somebody "
                        "else's work ships in this binary")
    elif "without restriction" not in LICENSE.read_text():
        problems.append("LICENSE.txt is not the license this bank was "
                        "vendored under; re-read it before shipping")

    # ------------------------------------------------- what the bank holds
    kits: dict[int, str] = {}
    if got == expected:
        try:
            banks = presets(BANK)
        except ValueError as exc:
            problems.append(f"the bank will not parse as a SoundFont: {exc}")
            banks = {}
        melodic = banks.get(MELODIC_BANK, {})
        absent = [p for p in range(128) if p not in melodic]
        if absent:
            problems.append(f"the melodic bank is missing programs {absent} -- "
                            "GeneralMIDI.melodic offers all 128")
        else:
            notes.append("melodic bank: all 128 programs present")
        for bank in PERCUSSION_BANKS:
            if banks.get(bank):
                kits = banks[bank]
                break
        if not kits:
            problems.append(f"no percussion bank (looked in {PERCUSSION_BANKS})")
        else:
            notes.append(f"percussion bank: {len(kits)} kits at "
                         f"{sorted(kits)}")

    # The catalogue is a claim ABOUT THIS FILE. It was read out of Apple's
    # .dls once and then outlived it by nine kits.
    if kits and GENERAL_MIDI.exists():
        offered = swift_kit_programs(GENERAL_MIDI.read_text())
        if not offered:
            problems.append("cannot read GeneralMIDI.kits out of the Swift")
        elif sorted(offered) != sorted(kits):
            problems.append(
                f"GeneralMIDI.kits offers {sorted(offered)} but the bank holds "
                f"{sorted(kits)} -- the picker would offer silence")
        else:
            notes.append(f"GeneralMIDI.kits matches the file's {len(kits)} kits")

    # --------------------------------------------------- how it is wired in
    project = PROJECT.read_text() if PROJECT.exists() else ""
    # One folder reference per target. The unit-test target has NO host app,
    # so it needs its own copy or every offline render measures the fallback.
    wired = re.findall(r"- path: Vendor/SoundFonts\b", project)
    if len(wired) < 2:
        problems.append(
            f"project.yml references Vendor/SoundFonts {len(wired)} time(s); "
            "the app target and ScorangerTests each need one, or the audio "
            "tests measure the sampler's fallback tone")
    else:
        notes.append(f"project.yml bundles it into {len(wired)} targets")

    # ---------------------------------------------------- and the mistake
    source = SOUND.read_text() if SOUND.exists() else ""
    for host in ("/System/", "/Library/"):
        if f'"{host}' in source or f"({host}" in source:
            problems.append(
                f"PlaybackSound.swift still names a host path under {host} -- "
                "that is the bug: it resolves in the simulator and not on an iPad")
    if "Bundle" not in source:
        problems.append("PlaybackSound.swift does not resolve the bank out of "
                        "a bundle, so nothing guarantees it is on the device")
    elif not any("host path" in p or "does not resolve" in p for p in problems):
        notes.append("PlaybackSound resolves it out of a bundle, "
                     "not an absolute host path")

    for note in notes:
        print(f"  ok   {note}")
    for problem in problems:
        print(f"  FAIL {problem}")
    if problems:
        print(f"\n{len(problems)} problem(s)"
              "\n  run: ios/scripts/fetch_soundfont.sh")
        return 1
    print("\nvendored sound bank: carried by the app")
    return 0


if __name__ == "__main__":
    sys.exit(main())
