# Licence texts that ship in the app

Each folder is the licence text of one credit on Settings › How Scoranger
works (`Pipeline.Credit.text`), copied into the bundle as `Licences/` and shown
by "Read the licence". `deploy_testflight.sh` refuses an archive that is
missing any path a credit names. Collected for 0.15.0, 2026-09-23.

A text belongs to a VERSION. When a dependency moves, the text moves with it:
re-copy it from the same source and update the version here.

| Folder | What | Source of each file |
|---|---|---|
| `python/` | the Python packages in `PythonApp/app_packages` | **generated** by `scripts/vendor_engine.sh` from each package's `.dist-info` (gitignored) |
| `cpython/` | CPython 3.14.6 (BeeWare 3.14-b10) and the C libraries its build carries | `CPython 3.14`: `Vendor/Python.xcframework/lib/python3.14/LICENSE.txt`. The rest at the versions in `Vendor/VERSIONS`, from each project's own repository at that release tag: OpenSSL `openssl-3.5.7` LICENSE.txt; XZ `v5.6.4` COPYING and COPYING.0BSD; Zstandard `v1.5.7` LICENSE; bzip2 `bzip2-1.0.8` LICENSE (sourceware.org); libffi `v3.4.7` LICENSE; mpdecimal 4.0.0 COPYRIGHT.txt, from the release tarball at bytereef.org |
| `verovio/` | Verovio 6.2.1 | `Vendor/verovio/COPYING` and `COPYING.LESSER`. LGPL-3.0 is GPL-3.0 plus additional permissions, so both travel |
| `verovio-libraries/` | code compiled inside Verovio | the notices in Verovio's own tree: `include/crc/crc.h`, `include/hum/humlib.h`, `include/json/LICENSE` (jsonxx), `include/pugi/pugixml.hpp`, `include/zip/zip_file.hpp` (miniz-cpp, and miniz inside it), `include/tuning-library/LICENSE.md`. Two are not in the tree: **midifile** has no notice in Verovio's copy, so its LICENSE.txt is from github.com/craigsapp/midifile (master; the version Verovio took is not recorded); **libmei**'s README states the MIT license and its generated files "Copyright (c) Authors and others", and the MIT terms written out under that are the standard text |
| `music-fonts/` | Bravura, Petaluma, Leland, Leipzig, Gootville | each font's copyright statement, read from its file under `Vendor/verovio/fonts/` (Petaluma's from its SVG metadata); the OFL 1.1 text from Bravura.otf's name table |
| `swiftdraw/` | SwiftDraw | its checkout's LICENSE.txt, at the version in `Package.resolved` |
| `google/` | Firebase and Google Sign-In, and what they link | `Firebase NOTICES` is the firebase-ios-sdk checkout's `CoreOnly/NOTICES`, Firebase's own aggregate: it covers the SDK, AppCheckCore, GTMSessionFetcher, Promises, RecaptchaInterop, GoogleUtilities, BoringSSL-GRPC, gRPC, abseil, leveldb, nanopb and Firestore's bundled code. What it does not cover is beside it, each from its checkout: GoogleSignIn, AppAuth, GTMAppAuth, and IsAppEncrypted (MIT, in GoogleUtilities/third_party) |

Also shipped, and not in this folder: the sound bank's `SoundFonts/LICENSE.txt`
and the three interface typefaces' `OFL-*.txt`, which already travelled with
the files they license.

What was linked was read from the BUILD PRODUCTS, not from `Package.resolved`:
SwiftProtobuf resolves and links into nothing, so it is not credited;
GoogleAppMeasurement and GoogleDataTransport likewise.

**Not shipped on purpose:** Verovio's `data/Liberation.css`, which embeds
Liberation Serif 1.04 (2007) -- GPLv2 with a font exception, not the OFL of
Liberation 2.x -- and which the app never loads. `scripts/fetch_python.sh`
removes it and `deploy_testflight.sh` refuses an archive that carries it.
