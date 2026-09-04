"""Opaque, stable identifiers for library documents.

Every score, piece, setlist, book and version carries one of these. They exist
because the library's old identifiers were derived from things that move:

  - a score's key was `slugify(title)`, so renaming an arrangement had to
    rewrite the key AND every reference to it (`rename_slug`); two people who
    both arrange "Morrison's Jig" would both own `morrisons-jig`.
  - a version's key was `v{count+1:03d}`, allocated by counting the rows that
    already existed. Read, then write, with no transaction: two devices working
    offline on the same arrangement both allocate `v031`, and one of them has
    to lose.

An identifier that names a thing must not be computable from that thing's
title or from how many siblings it happens to have. See design/FIREBASE.md §3.

ULID rather than UUID4 because it sorts by creation time as a plain string, to
the millisecond: `ls` in a score's directory still lists versions roughly in
the order they were made, which is what `vNNN` gave us and what a random id
would lose. Two ids minted inside the same millisecond sort arbitrarily, which
never matters here -- a version costs a music21 write, so they arrive seconds
apart -- and version ORDER is carried by `seq` regardless, never by the id.
48-bit millisecond timestamp, 80 bits of randomness, Crockford base32, 26
characters.

Implemented here in twenty lines rather than taken from PyPI on purpose: the
engine ships inside the iOS app with `music21` as its only dependency
(`engine/pyproject.toml`, `scripts/vendor_engine.sh`), and a new runtime
dependency has to be vendored onto the device to be worth anything.
"""

import os
import time

#: Crockford base32: no I, L, O or U, so an id read aloud or copied by hand
#: cannot turn into a different one.
_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

ID_LENGTH = 26

#: Matches an id and nothing else. Used to tell an id from a `vNNN` label when
#: resolving whatever the caller typed.
_ID_CHARS = set(_ALPHABET)


def _encode(value: int, length: int) -> str:
    out = []
    for _ in range(length):
        out.append(_ALPHABET[value & 0x1F])
        value >>= 5
    return "".join(reversed(out))


def new_id() -> str:
    """A fresh identifier. Monotonic enough to sort, random enough to not collide.

    Two devices generating one in the same millisecond differ in 80 random
    bits, which is the property the whole design rests on: allocation needs no
    coordination, so it works offline.
    """
    return (_encode(int(time.time() * 1000), 10)
            + _encode(int.from_bytes(os.urandom(10), "big"), 16))


def is_id(value) -> bool:
    """True for something new_id() could have produced.

    Deliberately strict: `resolve_version` uses this to decide whether the
    caller typed an identifier or a `v012` label, and a loose test would make
    a mistyped label look like a missing id.
    """
    return (isinstance(value, str) and len(value) == ID_LENGTH
            and all(c in _ID_CHARS for c in value))
