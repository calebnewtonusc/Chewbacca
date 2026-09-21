#!/usr/bin/env python3
"""The display has to be able to say why it is not on the screen.

Caleb merged the presence field on 2026-09-21 and saw no border on his Mac.
Four separate things could have caused that and every one of them was silent:
no app built (setup.sh linked the commands and only warned about the thing
that draws), an app built before the feature existed, a Metal shader that
would not compile, or a second monitor. Nothing he could run would have named
any of them, because doctor.sh had twenty sections and none of them knew the
display existed.

These are the checks that would have caught each of those, plus the one that
caught itself: the first version of the shader check matched the `log`
command's own argv and reported a broken GPU on a Mac whose GPU was fine.
"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
fails = []


def check(name, condition, detail=""):
    if condition:
        print(f"  pass  {name}")
    else:
        fails.append(name)
        print(f"  FAIL  {name}")
        if detail:
            print(f"        {detail}")


bundle = (ROOT / "hud" / "scripts" / "bundle.sh").read_text()
setup = (ROOT / "setup.sh").read_text()
doctor = (ROOT / "doctor.sh").read_text()
hud = (ROOT / "bin" / "hud").read_text()

# An architecture spelled out is a machine somebody else owns that cannot
# build this. SwiftPM writes x86_64-apple-macosx on an Intel Mac, and the
# build died at the copy having already compiled cleanly.
check(
    "bundle.sh asks SwiftPM where the binary is",
    "--show-bin-path" in bundle,
    "it should not spell out an architecture triple",
)
# Comments are exempt: the one in bundle.sh names the old hardcoded path on
# purpose, because a constant that carries its incident does not get put back.
bundle_code = "\n".join(
    l for l in bundle.splitlines() if not l.lstrip().startswith("#")
)
check(
    "bundle.sh hardcodes no architecture",
    not re.search(r"\.build/(arm64|x86_64)-apple", bundle_code),
)

# An install that ends in an instruction has not installed anything.
check(
    "setup.sh builds the display instead of printing a command",
    "bundle.sh release" in setup,
    "the HUD section should run bundle.sh, not only warn",
)

# The check that did not exist at all.
check("doctor.sh has a display section", 'section "The display"' in doctor)
check(
    "doctor.sh delegates to hud doctor rather than copying the chain",
    "doctor --no-lights" in doctor,
)

# Each link in the chain, by the symptom it explains.
for needle, why in [
    ("below the 14.0 floor", "macOS too old to launch the app"),
    ("nothing to draw on", "no app installed"),
    ("is at $head", "app older than the code that was merged"),
    ("installed but not running", "app present, never launched"),
    ("no socket at", "nothing can reach the glass"),
    ("Metal shader did not compile", "the field's one silent failure"),
    ("menu bar", "the border is on the other display"),
]:
    check(f"hud doctor explains: {why}", needle in hud)

# The check that reported a broken GPU on a working one. `log` writes its own
# argv into the log, predicate text included, so an unscoped query matches
# itself from its own first run onwards.
m = re.search(r"--predicate '([^']*presence field unavailable[^']*)'", hud)
check(
    "the shader query cannot match itself",
    bool(m) and 'process == "BobHUD"' in m.group(1),
    "scope the predicate to the process that emits the line",
)

# A health check that changes what is on the screen is not a health check.
# --no-lights is what doctor.sh and CI use.
nolights = hud[hud.find("hud_doctor()") :]
check(
    "--no-lights suppresses the live field",
    '"${1:-}" = "--no-lights"' in nolights and '"$live" -eq 1' in nolights,
)

# Behaviour, not text: pointed at a socket that is not there, it must name
# that and exit non-zero rather than exiting 0 with a clean bill.
with tempfile.TemporaryDirectory() as tmp:
    env = dict(os.environ, BOB_HUD_SOCKET=str(Path(tmp) / "absent.sock"))
    run = subprocess.run(
        [str(ROOT / "bin" / "hud"), "doctor", "--no-lights"],
        capture_output=True, text=True, env=env, timeout=120,
    )
    check("a missing socket is reported", "no socket at" in run.stdout, run.stdout[-400:])
    check("a broken chain exits non-zero", run.returncode != 0, f"exit {run.returncode}")
    check("--no-lights draws nothing", "Lighting the field" not in run.stdout)

print()
if fails:
    print(f"{len(fails)} failed")
    sys.exit(1)
print("all passed")
