#!/bin/bash
# Downloads the General MIDI sound bank the app PLAYS WITH into ios/Vendor/.
# Vendor/ is gitignored (large binaries, and this one is somebody else's work);
# run this once per clone, the same as fetch_python.sh.
#
# WHY THE APP CARRIES A BANK AT ALL. It used to load Apple's:
#
#   /System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls
#
# That is a macOS path. There is no `System/Library/Components` in the iOS SDK
# and none in the simulator runtime's root -- it resolved in the simulator only
# because a simulator process falls through to the HOST Mac's filesystem, where
# the file really does live. On an iPad `loadSoundBankInstrument` throws, and an
# `AVAudioUnitSampler` with no instrument loaded plays its own built-in tone: a
# near sine, the same one on every channel, deaf to every program change. Which
# is exactly what Ali reported. iOS ships no General MIDI bank an app may load,
# and Apple's is not redistributable, so the only fix is to bring one.
#
# WHY THIS ONE. GeneralUser GS, by S. Christian Collins: all 128 melodic
# programs and thirteen drum kits in 31MB, and a license (see LICENSE.txt
# beside the file) that reads "You may use GeneralUser GS without restriction
# for your own music creation, private or commercial ... Please feel free to
# use it in your software projects". The alternatives were FluidR3_GM, which is
# 148MB for the same coverage, and TimGM6mb, which is GPL and so a poor fit for
# an App Store binary.
#
# PINNED TO A COMMIT AND A DIGEST. The upstream repo publishes no tags, so a
# branch name is not an identity: `main` is whatever it is on the day of the
# clone. The commit is pinned and the file's sha256 is checked, so every clone
# and every archive gets the same 31MB.
set -euo pipefail
cd "$(dirname "$0")/.."

# GeneralUser GS v2.0.3, documentation r6 (2026-02-23)
COMMIT="684543d5e5efaef08d02be50dcda8d552478fa60"
SHA256="9575028c7a1f589f5770fccc8cff2734566af40cd26ed836944e9a5152688cfe"
RAW="https://raw.githubusercontent.com/mrbumpy409/GeneralUser-GS/$COMMIT"
DEST="Vendor/SoundFonts"
BANK="$DEST/GeneralUser-GS.sf2"

verify() {
  [[ -f "$BANK" ]] || return 1
  [[ "$(shasum -a 256 "$BANK" | cut -d' ' -f1)" == "$SHA256" ]]
}

if verify; then
  echo "$BANK already present and matches its digest."
  exit 0
fi
if [ -f "$BANK" ]; then
  echo "$BANK does not match its digest -- re-fetching."
  rm -f "$BANK"
fi

mkdir -p "$DEST"
echo "Fetching $RAW/GeneralUser-GS.sf2"
curl -L --fail --progress-bar -o "$BANK.part" "$RAW/GeneralUser-GS.sf2"
got=$(shasum -a 256 "$BANK.part" | cut -d' ' -f1)
if [[ "$got" != "$SHA256" ]]; then
  rm -f "$BANK.part"
  echo "digest mismatch: expected $SHA256, got $got" >&2
  exit 1
fi
mv "$BANK.part" "$BANK"

# The license TRAVELS WITH THE FILE, into the app bundle. Somebody else's work
# ships inside this binary and the terms it ships under should not be a line in
# a script that only the person who ran it ever read.
curl -L --fail --silent -o "$DEST/LICENSE.txt" "$RAW/documentation/LICENSE.txt"

echo "done: $(du -h "$BANK" | cut -f1) $BANK"
