# Scoranger for iPad

Native SwiftUI app with the **entire Scoranger engine embedded on-device** —
no laptop, no server:

- **Embedded engine**: CPython 3.14 + music21 run inside the app
  (`PythonApp/app/bridge.py` behind a C shim + Swift actor). Every arrangement
  op, harmony analysis, and the versioned workspace (SQLite, in the app's
  Documents) work offline.
- **On-device engraving**: Verovio (compiled in via SPM) renders MusicXML to
  SVG; a preprocessing pass adapts it for SwiftDraw, which produces the PDF
  pages.
- **Native chat agent**: a Swift tool loop over OpenRouter mirroring the
  engine's 21 arrangement tools. Add your OpenRouter API key in Settings
  (stored in the Keychain) and pick a model in the chat header.
- **Apple Pencil annotations** (pencil draws, fingers scroll; per page, per
  version), Files-app import (+), semitone transposition, version history.

A Settings toggle can still point the app at a Mac running
`scor serve --host 0.0.0.0` (remote mode, the original thin-client setup).

## Build & run

Two vendored pieces are gitignored and fetched by script; the Xcode project is
generated (not checked in):

```sh
brew install xcodegen              # once
cd ios
scripts/fetch_python.sh            # BeeWare Python.xcframework + verovio clone into Vendor/
scripts/vendor_engine.sh           # music21 + engine sources into PythonApp/
xcodegen generate
open Scoranger.xcodeproj
```

Re-run `vendor_engine.sh` whenever engine Python changes. In Xcode: select the
**Scoranger** target → *Signing & Capabilities* → pick your team, choose your
iPad, Run. (TestFlight builds: `xcodebuild archive` + export with
`build/ExportOptions.plist`.)

## Notes

- Annotations are stored on-device (Documents/annotations) keyed by
  score/version/page.
- The on-device workspace lives in the app's Documents/workspace (visible in
  the Files app); every mutation is an immutable version, same as the desktop
  engine.
- OMR (PDF → MusicXML) stays off-device — run Audiveris on a Mac and import
  the resulting `.mxl` via the Files picker.
