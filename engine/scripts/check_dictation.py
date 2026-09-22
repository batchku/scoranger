#!/usr/bin/env python3
"""No voice recorded by this app leaves the device.

`SFSpeechAudioBufferRecognitionRequest.requiresOnDeviceRecognition` defaults
to FALSE. A request that never sets it streams the microphone to Apple's
servers, on every device, whether or not that device could transcribe locally
-- and the app looks and behaves identically either way, which is why the
default stood unnoticed until design/CHILDRENS_PRIVACY_BRIEF.md 7.1 counted
the matches (zero, across all Swift).

It matters beyond housekeeping. COPPA 312.2(8) counts "an audio file where
such file contains a child's image or voice" as personal information, and
312.2(10), new in 2025, counts a voiceprint as a biometric identifier. A known
under-13 user makes both live. On-device recognition removes the question
rather than fitting the app inside 312.5(c)(9)'s narrow exception. It is also
what lets the App Privacy questionnaire answer Audio Data "No"
(design/APP_STORE_PRIVACY.md 3.2).

WHAT IS ASSERTED, and why each one:

  1. The flag is SET, and set TRUE. A default is not a decision.
  2. There is NO FALLBACK. `requiresOnDeviceRecognition` is assigned exactly
     once and from a literal, never from a variable or a condition -- a
     fallback would be invisible to the user and would make the Info.plist
     strings below untrue some of the time.
  3. It is GUARDED by `supportsOnDeviceRecognition`, and guarded BEFORE the
     audio session opens. Asking for on-device recognition where it is
     unsupported fails inside the recognition task instead, which is after the
     microphone is live: audio recorded with nowhere to send it.
  4. The refusal SAYS SOMETHING. `errorText` is the chat field's placeholder,
     so a guard that returned silently would read as a dead microphone.
  5. The two Info.plist strings -- the only place a user is ever told where
     their voice goes -- SAY on-device, in BOTH the generated Info.plist and
     project.yml, which is the file that wins when the project is regenerated.

Read out of the source rather than run: ScorangerTests has no host app and
cannot import the app target, and the behaviour under test is one property on
an Apple request object.

Run: engine/.venv/bin/python engine/scripts/check_dictation.py
"""
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "ios" / "Scoranger" / "SpeechDictation.swift"
PLIST = ROOT / "ios" / "Scoranger" / "Info.plist"
PROJECT = ROOT / "ios" / "project.yml"

FAILURES: list[str] = []


def check(ok: bool, label: str) -> None:
    print(f"    {'ok  ' if ok else 'FAIL'} {label}")
    if not ok:
        FAILURES.append(label)


def code_of(path: Path) -> str:
    """Source with comments dropped.

    Every assertion below is about CODE. The first draft of this passed on a
    tree where the only `requiresOnDeviceRecognition` in the file was the
    sentence explaining what it does -- a check reading its own
    documentation, which is the failure mode this repo keeps rediscovering.
    """
    return "\n".join(line for line in path.read_text().splitlines()
                     if not line.lstrip().startswith("//"))


def dictation_is_on_device() -> int:
    print("\nthe microphone is transcribed on the device")
    check(SRC.is_file(), f"{SRC.relative_to(ROOT)} exists")
    if not SRC.is_file():
        return 1
    code = code_of(SRC)

    # 1 + 2: set, true, once, from a literal.
    assigns = re.findall(r"requiresOnDeviceRecognition\s*=\s*([^\n]+)", code)
    check(len(assigns) == 1,
          f"requiresOnDeviceRecognition is assigned exactly once in code; "
          f"found {len(assigns)}: {assigns}")
    check(assigns == ["true"],
          f"and it is assigned the literal true -- not a variable, not a "
          f"condition, so there is no path that sends audio to a server; "
          f"got {assigns}")

    # 3: guarded, and guarded first.
    check("supportsOnDeviceRecognition" in code,
          "supportsOnDeviceRecognition is consulted, so an unsupported "
          "device is refused rather than failing after the mic opens")
    guard_at = code.find("supportsOnDeviceRecognition")
    session_at = code.find("audioEngine.start")
    tap_at = code.find("installTap")
    check(guard_at != -1 and session_at != -1 and guard_at < session_at,
          f"the guard runs BEFORE the audio engine starts "
          f"({guard_at} < {session_at})")
    check(guard_at != -1 and tap_at != -1 and guard_at < tap_at,
          f"and before the microphone tap is installed ({guard_at} < {tap_at})")

    # 4: and it says so.
    guard_block = code[guard_at:code.find("}", guard_at)] if guard_at != -1 else ""
    check("errorText" in guard_block,
          "the refusal sets errorText, which is the chat field's placeholder "
          "-- a silent guard reads as a dead microphone")

    # 5: the strings a user actually sees.
    with PLIST.open("rb") as handle:
        info = plistlib.load(handle)
    project = PROJECT.read_text()
    for key in ("NSSpeechRecognitionUsageDescription",
                "NSMicrophoneUsageDescription"):
        text = info.get(key, "")
        check("on this device" in text.lower(),
              f"{key} tells the user the audio stays on the device; "
              f"got {text!r}")
        # project.yml is the source: Xcode regenerates the built Info.plist
        # from it, so a string fixed only in the plist is a string that
        # disappears at the next `xcodegen`.
        check(text and f'{key}: "{text}"' in project,
              f"and project.yml carries the same {key}, so regenerating the "
              f"project does not undo it")
    return 0


def main() -> int:
    dictation_is_on_device()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: dictation is on-device only, refused where it cannot be, and "
          "the\n    permission prompts say so")
    return 0


if __name__ == "__main__":
    sys.exit(main())
