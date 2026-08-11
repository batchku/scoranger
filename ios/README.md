# Scoranger for iPad

Native SwiftUI client of the Scoranger engine: score library, versions and
sources, Verovio-engraved score pages, **Apple Pencil annotations** (pencil
draws, fingers scroll; per page, per version), the arrangement **chat agent**
with a model picker, and semitone transposition.

The app is a thin client — all musical intelligence stays in the engine.

## Build & run

The Xcode project is generated (not checked in):

```sh
brew install xcodegen        # once
cd ios && xcodegen generate
open Scoranger.xcodeproj
```

In Xcode: select the **Scoranger** target → *Signing & Capabilities* → pick
your team (personal Apple ID works for device installs), then choose your iPad
in the run destination and hit Run. First install on-device requires trusting
the developer profile in iPad Settings → General → VPN & Device Management.

## Connect to the engine

On the Mac, run the engine listening on the LAN:

```sh
engine/.venv/bin/scor serve --host 0.0.0.0
```

In the app, open **Settings (gear)** and set the engine URL to your Mac, e.g.
`http://Alis-MacBook-Pro.local:8765` (hostname from macOS System Settings →
General → Sharing). The status dot turns green when connected.

## Notes

- Annotations are stored on-device (Documents/annotations) keyed by
  score/version/page; server-side annotation sync is a planned feature.
- Chat uses the engine's model catalog (`/api/models`); pick per-conversation
  in the chat header or set the default in Settings.
- The score view auto-follows the latest version as the agent works — from the
  iPad, the web viewer, or a Claude Code session on the Mac; all clients share
  the same live library.
