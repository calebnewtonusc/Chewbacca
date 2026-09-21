#!/usr/bin/env python3
"""bin/lib/axgrant.py: telling a live Accessibility grant from a dead one.

The bytes in here are not invented. They were read out of this Mac's TCC
database on 2026-09-21, and the two shapes are the whole point of the file: the
microphone grant stored the bundle identifier and survived every rebuild that
day, while the Accessibility grant stored a hash and died at the first one. The
switch in System Settings said "on" for both.

Nothing here touches the real database and nothing calls tccutil.
"""

from __future__ import annotations

import importlib.util
import sqlite3
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("axgrant", ROOT / "bin" / "lib" / "axgrant.py")
axgrant = importlib.util.module_from_spec(spec)
spec.loader.exec_module(axgrant)

# Read from /Library/Application Support/com.apple.TCC/TCC.db on 2026-09-21.
# The grant was recorded at 05:13:59 and the bundle was rebuilt at 13:40:12.
CDHASH_REQ = bytes.fromhex(
    "FADE0C00000000280000000100000008000000142EFEDDB7A49900F9F1D0D2A27E1EA2298B806558")
GRANTED_TO = "2efeddb7a49900f9f1d0d2a27e1ea2298b806558"
REBUILT_AS = "a4246cb7228c1b8662ccd2972f304ce75777334b"
# The microphone row, from the user database, same app, same ad-hoc signature.
IDENT_REQ = bytes.fromhex(
    "FADE0C000000002C0000000100000002000000156465762E626F627468656275696C6465722E687564000000")

failures = 0


def check(name: str, ok: bool, detail: str = "") -> None:
    global failures
    print(f"  {'ok  ' if ok else 'FAIL'} {name}" + (f": {detail}" if detail and not ok else ""))
    if not ok:
        failures += 1


def a_db(csreq: bytes | None, auth: int = 2) -> Path:
    """A TCC-shaped database holding one row, or none."""
    path = Path(tempfile.mkdtemp()) / "TCC.db"
    con = sqlite3.connect(path)
    con.execute(
        "create table access (service text, client text, client_type int, "
        "auth_value int, csreq blob)")
    if csreq is not None:
        con.execute(
            "insert into access values ('kTCCServiceAccessibility', "
            "'dev.bobthebuilder.hud', 0, ?, ?)", (auth, csreq))
    con.commit()
    con.close()
    return path


def main() -> int:
    print("axgrant: reading a code requirement")
    check("a hash-pinned requirement gives up its hash",
          axgrant.pinned_hash(CDHASH_REQ) == GRANTED_TO,
          str(axgrant.pinned_hash(CDHASH_REQ)))
    check("an identifier-pinned requirement pins no hash",
          axgrant.pinned_hash(IDENT_REQ) is None)
    check("a truncated requirement is not guessed at",
          axgrant.pinned_hash(CDHASH_REQ[:14]) is None)
    check("something that is not a requirement is not guessed at",
          axgrant.pinned_hash(b"not a requirement at all") is None)
    check("a hash longer than the blob is refused",
          axgrant.pinned_hash(CDHASH_REQ[:24]) is None)

    print("axgrant: the state of a grant")
    real = axgrant.bundle_hash
    axgrant.bundle_hash = lambda app=None: REBUILT_AS
    try:
        check("a grant pinned to an older build is stale",
              axgrant.state(db=a_db(CDHASH_REQ)) == "stale")
        axgrant.bundle_hash = lambda app=None: GRANTED_TO
        check("a grant pinned to this build is ok",
              axgrant.state(db=a_db(CDHASH_REQ)) == "ok")
        axgrant.bundle_hash = lambda app=None: REBUILT_AS
        check("a grant naming the identifier is ok whatever the build",
              axgrant.state(db=a_db(IDENT_REQ)) == "ok")
        check("no row is absent, not stale",
              axgrant.state(db=a_db(None)) == "absent")
        check("a grant that is switched off is absent, not stale",
              axgrant.state(db=a_db(CDHASH_REQ, auth=0)) == "absent")
        check("a database that is not there is unknown, never a refusal",
              axgrant.state(db=Path("/nowhere/TCC.db")) == "unknown")
        axgrant.bundle_hash = lambda app=None: None
        check("no app on disk is unknown, never a refusal",
              axgrant.state(db=a_db(CDHASH_REQ)) == "unknown")
    finally:
        axgrant.bundle_hash = real

    # Scanning must not write. `repair` throws away a permission, so the one
    # thing it must never do is run on a reading it did not take itself.
    print("axgrant: repair only ever writes on a stale reading")
    ran = []

    class Loud:
        def __call__(self, *a, **k):
            ran.append(a)
            raise AssertionError("tccutil was run on a grant that was not stale")

    real_run, real_state = axgrant.subprocess.run, axgrant.state
    axgrant.subprocess.run = Loud()
    try:
        for reading in ("ok", "absent", "unknown"):
            axgrant.state = lambda *a, _r=reading, **k: _r
            check(f"a grant reading {reading} is left alone", axgrant.repair() is False)
    finally:
        axgrant.subprocess.run, axgrant.state = real_run, real_state
    check("nothing was run", not ran)

    print(f"\n{'FAILED' if failures else 'passed'}: {failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
