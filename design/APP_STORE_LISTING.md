# App Store listing — Scoranger

*Draft for App Store Connect. Every field below is one the submission asks for.
Character limits are Apple's and are counted here. Nothing is published by this
document.*

---

## Name (30 max)

`Scoranger` — 9

## Subtitle (30 max)

`Arrange music by asking` — 23

Alternatives, same limit:
- `Rewrite scores in plain words` — 29
- `Your score, your instruments` — 28

## Promotional text (170 max, editable without review)

`Bring in a score, say what you want, and it rewrites the notation. Now reads ABC tunes, carries ornaments through, and can combine pieces.` — 137

## Description (4000 max)

Scoranger rewrites musical scores for the instruments you actually have.

Bring in a score and say what you want in plain words. "Keep the violins, turn
the viola and cello into an accordion left hand, add chord symbols." It carries
that out and hands you back real notation.

The arranging is done by music software, not by a language model writing notes.
The chat works out what you asked for and then calls the operations that do the
work, so what comes back is correct notation rather than a guess at it. Nothing
is overwritten: every change makes a new version, labelled with what made it,
and you can go back to any of them.

WHAT IT DOES

• Transpose by interval, or by scale degree so a harmony line stays in the key
• Merge staves, split a part into bass and chords, fit a line to an instrument's
  range and clef
• Add and edit chord symbols, guitar tab, chord diagrams and penny-whistle
  fingerings
• Repeats, voltas, rehearsal marks, dynamics, ornaments and articulations
• Play the arrangement back with a click, and read from it with a moving cursor
• Mark up any page with the Apple Pencil
• Export as MusicXML, MIDI or PDF, or hand a whole set list to someone as a file

WHAT IT READS

MusicXML, MIDI and ABC come in as notation. ABC tunes from sites like
thesession.org import as one arrangement per tune, ornaments included.

A PDF or a photograph of a page can be read and marked up as it is, or converted
into editable notation. Conversion is automatic reading of printed music: good
on clean engraved pages, weaker on handwriting and faint photocopies. What you
get is a draft to correct, which is why the original stays beside it.

ON THE DEVICE

The engine runs on your iPad. Importing, arranging, engraving, playback, pencil
marks and export all work with no network at all. Two things need one: the chat,
and converting a scan into notation.

No account is required, ever. Your library is yours and stays on your iPad. Sign
in only if you want to share a set list with the people you play with.

FOR WHOM

Composers, arrangers and working musicians who have a score in one shape and
need it in another.

## Keywords (100 max, comma-separated, no spaces after commas)

`sheet music,score,arranger,transpose,musicxml,notation,abc,setlist,chords,tab,composer,midi,pdf` — 97

## Category

- Primary: **Music**
- Secondary: **Productivity**

## Age rating

Expected **4+**. Every content descriptor NONE. Not made for kids, no Kids
Category. See `design/CHILDRENS_PRIVACY_BRIEF.md` for the reasoning and for
the one question the chat raises.

## Content rights

Uses third-party content: see `design/APP_STORE_PRIVACY.md` §10 and the
attribution screen in Settings. The declaration itself is a single yes/no with
no upload.

## URLs

- Support: **https://batchku.github.io/scoranger-support/** (live)
- Privacy policy: **https://scoranger.web.app/privacy/** (live 2026-09-22; built by `firebase/build_hosting.sh` from `design/privacy-policy.md`)
- Marketing: none

## Screenshots

Only two sizes are gated; Apple derives the rest.
- iPhone 6.5-inch — 1284 x 2778
- iPad 13-inch — 2048 x 2732

Shoot from `design/shots-0.12.0/`: the library, a score being read, the chat
mid-arrangement, the mixer, and a marked-up page.

## What's New

Written per release, diffed from the previous build's commits — never from
memory of what was worked on. See the memory note on release notes.
