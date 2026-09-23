#!/usr/bin/env python3
"""Whether an Accessibility grant still belongs to the app that is installed.

A grant can be switched on in System Settings and mean nothing. macOS does not
store "this app may do it"; it stores a code requirement, and for an ad-hoc
signature with no team identifier the only thing it can pin is the binary's own
hash. Every rebuild produces a new hash, so the row keeps saying "allowed" about
a build that no longer exists while `AXIsProcessTrusted()` answers false.

That is not a hypothetical. On 2026-09-21 the grant for dev.bobthebuilder.hud
was recorded at 05:13:59 against cdhash 2efeddb7a49900f9f1d0d2a27e1ea2298b806558.
The bundle was rebuilt at 13:40:12 as a4246cb7228c1b8662ccd2972f304ce75777334b.
The toggle stayed on, the display logged `bubble.bind refused reason=accessibility
not granted` three times, and every click of the bubble opened the same dialogue
asking for a permission the person had already given. There is nothing they can
do about that from System Settings, because the switch is already where they put
it.

Reading is free and writing is not: `state()` only looks, and `repair()` clears
the dead row so the next launch asks for real. Nothing here can grant anything.

The user-level services do not have this problem and show why. Microphone and
speech recognition were recorded the same way on 2026-09-19 and stored
`identifier "dev.bobthebuilder.hud"` instead of a hash, so they survive a
rebuild. The cure for Accessibility is the same one: sign with a certificate
that stays put, which is what `hud/scripts/bundle.sh` does whenever it can find
one in the keychain.
"""

from __future__ import annotations

import binascii
import subprocess
import sys
from pathlib import Path

SYSTEM_TCC = Path("/Library/Application Support/com.apple.TCC/TCC.db")
CLIENT = "dev.bobthebuilder.hud"
APP = Path("/Applications/Kyber.app")

# Opcodes of a code requirement's first term, from the Security framework's
# requirement language. Only these two are answerable: anything else is a real
# expression tree and this file declines to guess at it.
OP_IDENT = 2
OP_CDHASH = 8


def stored_requirement(client: str = CLIENT, db: Path = SYSTEM_TCC) -> bytes | None:
    """The requirement macOS holds for this client's Accessibility grant.

    None when the row is absent or the database cannot be read. The database is
    protected, so this answers only where the caller already holds Full Disk
    Access, and a None must never be reported as "not granted".
    """
    try:
        out = subprocess.run(
            ["/usr/bin/sqlite3", str(db),
             "select hex(csreq) from access "
             f"where service='kTCCServiceAccessibility' and client='{client}' "
             "and auth_value=2;"],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    hexed = out.stdout.strip()
    if not hexed:
        return None
    try:
        return binascii.unhexlify(hexed)
    except binascii.Error:
        return None


def pinned_hash(csreq: bytes) -> str | None:
    """The code hash a requirement is pinned to, if it is pinned to one.

    None means it is not hash-pinned, which is the good case: a requirement
    naming the identifier or a certificate outlives every rebuild.
    """
    # magic (4) + total length (4) + version (4), then the first term.
    if len(csreq) < 20 or csreq[:4] != b"\xfa\xde\x0c\x00":
        return None
    opcode = int.from_bytes(csreq[12:16], "big")
    if opcode != OP_CDHASH:
        return None
    size = int.from_bytes(csreq[16:20], "big")
    body = csreq[20:20 + size]
    if len(body) != size:
        return None
    return body.hex()


def bundle_hash(app: Path = APP) -> str | None:
    """The code hash of the bundle sitting on disk right now."""
    if not app.exists():
        return None
    try:
        out = subprocess.run(
            ["/usr/bin/codesign", "-dvvv", str(app)],
            capture_output=True, text=True, timeout=20,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    for line in (out.stderr + out.stdout).splitlines():
        if line.startswith("CandidateCDHash "):
            return line.split("=", 1)[1].strip().lower()
    return None


def state(client: str = CLIENT, app: Path = APP, db: Path = SYSTEM_TCC) -> str:
    """One of: unknown, absent, ok, stale.

    `stale` is the only one worth acting on and the only one a person cannot
    diagnose from System Settings, because there the switch reads as on.
    """
    csreq = stored_requirement(client, db)
    if csreq is None:
        return "unknown" if not db.exists() or not _readable(db) else "absent"
    pinned = pinned_hash(csreq)
    if pinned is None:
        return "ok"
    current = bundle_hash(app)
    if current is None:
        return "unknown"
    return "ok" if pinned == current else "stale"


def _readable(db: Path) -> bool:
    try:
        with db.open("rb"):
            return True
    except OSError:
        return False


def repair(client: str = CLIENT) -> bool:
    """Clear a grant that points at a build that no longer exists.

    This throws away a permission, so it runs only against `stale`. The row it
    removes authorises nothing: leaving it in place is what produces a toggle
    that is on and an app that is refused. Afterwards the next launch asks, and
    the answer lands on the binary that is actually there.
    """
    if state(client) != "stale":
        return False
    try:
        done = subprocess.run(
            ["/usr/bin/tccutil", "reset", "Accessibility", client],
            capture_output=True, text=True, timeout=20,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return done.returncode == 0


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    now = state()
    if "--repair" in args:
        if now != "stale":
            return 0
        if repair():
            print("  accessibility: cleared a grant left behind by an older build")
            print("  it will ask once more, and this time the answer sticks")
            return 0
        print("  accessibility: a grant points at an older build and could not be cleared")
        print(f"  run: tccutil reset Accessibility {CLIENT}")
        return 1
    print(now)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
