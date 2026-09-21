#!/usr/bin/env bash
# Shoot a demo of the display answering a question.
#
# The thing being demonstrated is one job, start to finish: somebody asks their
# screen for something and the answer arrives on the glass, with the edge of the
# display saying what is happening the whole time. Two features, no tour. Every
# practitioner who makes these for a living names showing many features as the
# single biggest mistake, and a HUD is unusually easy to over-show because it
# can draw anything.
#
# The awkward fact this script exists to handle: a real request takes about
# thirty five seconds and a demo has twelve. The wait is not the product, so it
# is cut, and the two beats either side of it are kept whole. Nothing is sped
# up: a speed ramp over a field that pulses at 0.8Hz turns the one motion the
# viewer is meant to read into a flicker.
#
#   scripts/demo.sh "what is on my calendar tomorrow" out/demo
#
# Leaves <out>.mp4 beside the capture, and keeps the raw .cap so a second cut
# does not need a second take.
set -euo pipefail

SAID="${1:?say what to ask it}"
OUT="${2:-$HOME/Movies/hud-demo}"
SCREEN="${DEMO_SCREEN:-}"
SOCK="${BOB_HUD_SOCKET:-$HOME/.bob/hud.sock}"

command -v cap >/dev/null || { echo "cap is not installed" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg is not installed" >&2; exit 1; }
[ -S "$SOCK" ] || { echo "the display is not running: hud open" >&2; exit 1; }

# The primary screen, unless told otherwise. `cap record screens` reports every
# display and the ids are not the indices, so this reads the id rather than
# counting.
if [ -z "$SCREEN" ]; then
  SCREEN=$(cap record screens --json | python3 -c \
    'import json,sys; s=json.load(sys.stdin); print(next(d["id"] for d in s if d.get("primary")))')
fi

mkdir -p "$(dirname "$OUT")"
CAP="$OUT.cap"
rm -rf "$CAP"

# Start clean. A panel left over from the last take is the kind of thing nobody
# notices until the export is done.
printf 'hud clear\n' >/dev/null
hud clear >/dev/null 2>&1 || true
printf 'p dormant\n' | nc -U "$SOCK" || true
sleep 1

echo "recording screen $SCREEN"
cap record start --screen "$SCREEN" --detach --fps 60 --path "$CAP" >/dev/null
START=$(python3 -c 'import time; print(time.time())')

# The ask. Sent through the same bridge the microphone uses, so the footage is
# of the real path: `p thinking` on receipt, `p acting` on the first tool call,
# the panel drawn by the agent itself, `p done` when it lands.
ASKED=$(python3 - "$SAID" <<'PY'
import importlib.machinery, importlib.util, os, sys, time
loader = importlib.machinery.SourceFileLoader(
    "hudlisten", os.path.expanduser("~/.local/bin/hud-listen"))
spec = importlib.util.spec_from_loader("hudlisten", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)

listener = m.Listener("claude -p --strict-mcp-config --model sonnet", True, False)
listener.sock.connect(os.path.expanduser("~/.bob/hud.sock"))
marks = {}


def stamped(line: str) -> None:
    # When each state landed, relative to the start of the take. This is what
    # makes the cut repeatable: without it the beats are found by scrubbing.
    state = line.split()[-1] if line.startswith("p ") else None
    if state and state not in marks:
        marks[state] = time.time()
    original(line)


original = listener.send
listener.send = stamped
t0 = time.time()
listener._ask(sys.argv[1])
print(" ".join(f"{k}={v - t0:.2f}" for k, v in marks.items()))
PY
)
echo "beats: $ASKED"

sleep 2
cap record stop --path "$CAP" >/dev/null
echo "captured $CAP"

cap export "$CAP" --output "$OUT-raw.mp4" >/dev/null
echo "exported $OUT-raw.mp4"

# The cut. Three beats, joined with no transition: the ask, the work, the
# answer. A camera cut has to be a content cut, and the only content cut
# available here is the one this makes, from the moment work starts to the
# moment the panel exists.
python3 - "$OUT" "$ASKED" <<'PY'
import subprocess, sys, shlex
out, beats = sys.argv[1], dict(
    (k, float(v)) for k, v in (b.split("=") for b in sys.argv[2].split()))
raw = f"{out}-raw.mp4"

ask = beats.get("thinking", 0.0)
work = beats.get("acting", ask + 1.5)
done = beats.get("done", work + 3.0)

# 3s of the ask and the white field, 3s of green work, 6s of the answer
# landing and holding. Twelve total, and the ending is the part protected:
# a tail that gets shaved is a demo with no payoff in it.
cuts = [(max(ask - 1.0, 0), 3.0), (work, 3.0), (max(done - 2.0, work + 3.0), 6.0)]
parts = []
for i, (start, dur) in enumerate(cuts):
    part = f"{out}-part{i}.mp4"
    subprocess.run(
        ["ffmpeg", "-y", "-ss", f"{start:.2f}", "-t", f"{dur:.2f}", "-i", raw,
         "-c:v", "libx264", "-crf", "18", "-preset", "slow", "-an", part],
        check=True, capture_output=True)
    parts.append(part)

listfile = f"{out}-parts.txt"
with open(listfile, "w") as fh:
    for part in parts:
        fh.write(f"file {shlex.quote(part)}\n")
subprocess.run(
    ["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", listfile,
     "-c", "copy", f"{out}.mp4"], check=True, capture_output=True)
print(f"wrote {out}.mp4")
PY
